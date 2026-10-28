/* Keccak-256 (Ethereum). Pure JS, BigInt lanes. Shared by the Worker and the admin page. */
const KRC=[0x0000000000000001n,0x0000000000008082n,0x800000000000808An,0x8000000080008000n,0x000000000000808Bn,0x0000000080000001n,0x8000000080008081n,0x8000000000008009n,0x000000000000008An,0x0000000000000088n,0x0000000080008009n,0x000000008000000An,0x000000008000808Bn,0x800000000000008Bn,0x8000000000008089n,0x8000000000008003n,0x8000000000008002n,0x8000000000000080n,0x000000000000800An,0x800000008000000An,0x8000000080008081n,0x8000000000008080n,0x0000000080000001n,0x8000000080008008n];
const KR=[[0,36,3,41,18],[1,44,10,45,2],[62,6,43,15,61],[28,55,25,21,56],[27,20,39,8,14]];
const KM=(1n<<64n)-1n;
const krot=(x,n)=>n?(((x<<BigInt(n))|(x>>BigInt(64-n)))&KM):x;
function kf(A){
  for(const rc of KRC){
    const C=[0,1,2,3,4].map(x=>A[x][0]^A[x][1]^A[x][2]^A[x][3]^A[x][4]);
    const D=[0,1,2,3,4].map(x=>C[(x+4)%5]^krot(C[(x+1)%5],1));
    A=A.map((col,x)=>col.map(v=>v^D[x]));
    const B=[0,1,2,3,4].map(()=>[0n,0n,0n,0n,0n]);
    for(let x=0;x<5;x++)for(let y=0;y<5;y++)B[y][(2*x+3*y)%5]=krot(A[x][y],KR[x][y]);
    A=[0,1,2,3,4].map(x=>[0,1,2,3,4].map(y=>B[x][y]^((~B[(x+1)%5][y]&KM)&B[(x+2)%5][y])));
    A[0][0]^=rc;
  }
  return A;
}
function keccak256(data){ /* data: Uint8Array -> Uint8Array(32) */
  const rate=136,p=Array.from(data);p.push(1);
  while(p.length%rate)p.push(0);
  p[p.length-1]|=0x80;
  let A=[0,1,2,3,4].map(()=>[0n,0n,0n,0n,0n]);
  for(let off=0;off<p.length;off+=rate){
    for(let i=0;i<rate/8;i++){let v=0n;for(let j=7;j>=0;j--)v=(v<<8n)|BigInt(p[off+i*8+j]);A[i%5][Math.floor(i/5)]^=v}
    A=kf(A);
  }
  const out=[];
  for(let i=0;i<4;i++){let v=A[i%5][Math.floor(i/5)];for(let j=0;j<8;j++){out.push(Number(v&0xFFn));v>>=8n}}
  return Uint8Array.from(out);
}
const toHex=u=>Array.from(u).map(b=>b.toString(16).padStart(2,"0")).join("");
const utf8=s=>new TextEncoder().encode(s);
/* EIP-55 checksum address */
function checksumAddr(a){const l=a.toLowerCase().replace(/^0x/,""),h=toHex(keccak256(utf8(l)));let o="0x";for(let i=0;i<40;i++)o+=parseInt(h[i],16)>=8?l[i].toUpperCase():l[i];return o}
/* KAMBIODEX logo service (Cloudflare Pages advanced mode _worker.js).
   GET  /logo/<0xaddress>   -> PNG from KV (404 if none)
   POST /api/logo           -> JSON {action:"put"|"delete", token, ts, sig, png?(base64)}; only wallets listed in env.LOGO_ADMINS may write.
   The signature is a personal_sign over a fixed text that includes the token, the action, the time and the SHA-256 of the image.
   The signer is recovered with the ecrecover precompile through eth_call (no heavy maths inside the Worker). */
const RPCH="https://polygon-bor-rpc.publicnode.com";
const CSP_TAIL="; font-src data:; base-uri 'none'; form-action 'none'; object-src 'none'; frame-ancestors 'none'";
const CSP_SITE="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; connect-src 'self' "+RPCH+CSP_TAIL;
const CSP_ADMIN="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data: blob: https:; connect-src 'self' "+RPCH+" https://raw.githubusercontent.com https://tokens.uniswap.org https://static.metamask.io https://api.coingecko.com"+CSP_TAIL;
/* ---- /rpc: same-origin JSON-RPC proxy with automatic fallback between providers.
   Secrets (full URLs incl. API key) live only in Cloudflare: RPC_ALCHEMY, RPC_ANKR (optional), RPC_PUBLIC (optional). ---- */
const RPC_OK=new Set(["eth_call","eth_getLogs","eth_blockNumber","eth_chainId","eth_getBalance","eth_getCode","eth_getBlockByNumber","eth_getTransactionReceipt","eth_getTransactionByHash","eth_getTransactionCount","eth_estimateGas","eth_gasPrice","eth_maxPriorityFeePerGas","eth_feeHistory","eth_getStorageAt","net_version"]);
const upstreams=env=>[["alchemy",env.RPC_ALCHEMY],["ankr",env.RPC_ANKR],["public",env.RPC_PUBLIC||RPCH]].filter(x=>x[1]&&/^https:\/\//.test(x[1]));
const isLimitErr=e=>e&&(e.code===-32005||e.code===429||/rate|limit|capacity|exceed|too many|free tier|range|quota|throttl/i.test(String(e.message||"")));
async function upstreamCall(env,bodyText){
  for(const [name,url] of upstreams(env)){
    try{
      const r=await fetch(url,{method:"POST",headers:{"content-type":"application/json"},body:bodyText,signal:AbortSignal.timeout(7000)});
      if(!r.ok)continue;
      const t=await r.text();let j;try{j=JSON.parse(t)}catch(e){continue}
      if((Array.isArray(j)?j:[j]).some(x=>x&&isLimitErr(x.error)))continue;
      return [name,t];
    }catch(e){}
  }
  return null;
}
async function rpcProxy(req,env,u){
  const o=req.headers.get("origin");if(o&&new URL(o).host!==u.host)return J({error:"origin"},403);
  const text=await req.text();if(text.length>200000)return J({error:"size"},413);
  let b;try{b=JSON.parse(text)}catch(e){return J({error:"json"},400)}
  const arr=Array.isArray(b)?b:[b];
  if(arr.length<1||arr.length>50||!arr.every(x=>x&&typeof x.method==="string"&&RPC_OK.has(x.method)))return J({error:"method"},403);
  /* v22: short edge cache for read-only calls, so repeated identical reads do not burn provider quota.
     Never cached: receipts, tx lookups, nonce, gas, estimateGas (must stay fresh after the user's own transactions). */
  const CACHEABLE=new Set(["eth_call","eth_getLogs","eth_blockNumber","eth_chainId","eth_getBalance","eth_getCode","eth_getBlockByNumber","eth_getStorageAt","net_version"]);
  let ttl=0,ckey=null;
  if(arr.every(x=>CACHEABLE.has(x.method))){
    const live=/"latest"|"pending"|"safe"|"finalized"/.test(text)||arr.some(x=>x.method==="eth_blockNumber");
    const logs=arr.some(x=>x.method==="eth_getLogs");
    ttl=arr.every(x=>x.method==="eth_chainId"||x.method==="net_version"||x.method==="eth_getCode")?3600:(live?(logs?15:4):600);
    try{ckey=new Request("https://rpc-cache.kambiodex.internal/"+await sha256hex(utf8(text)))}catch(e){ckey=null}
    if(ckey){
      try{const hit=await caches.default.match(ckey);if(hit)return new Response(hit.body,{headers:{"content-type":"application/json","cache-control":"no-store","x-content-type-options":"nosniff","x-rpc-source":"cache"}})}catch(e){}
    }
  }
  const r=await upstreamCall(env,text);
  if(!r)return J({error:"upstream"},503);
  if(ckey&&ttl){try{await caches.default.put(ckey,new Response(r[1],{headers:{"content-type":"application/json","cache-control":"public, max-age="+ttl}}))}catch(e){}}
  return new Response(r[1],{headers:{"content-type":"application/json","cache-control":"no-store","x-content-type-options":"nosniff","x-rpc-source":r[0]}});
}
const ADDR_RE=/^0x[0-9a-fA-F]{40}$/;
const MAXPNG=60000;
const J=(o,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{"content-type":"application/json","cache-control":"no-store","x-content-type-options":"nosniff"}});
const b64d=s=>{const b=atob(s),u=new Uint8Array(b.length);for(let i=0;i<b.length;i++)u[i]=b.charCodeAt(i);return u};
async function sha256hex(u){return toHex(new Uint8Array(await crypto.subtle.digest("SHA-256",u)))}
const msgFor=(action,token,sha,ts)=>`KAMBIODEX logo\naction: ${action}\ntoken: ${token.toLowerCase()}\nsha256: ${sha}\nts: ${ts}`;
async function recoverSigner(env,msg,sig){
  const m=utf8(msg),pre=utf8("\x19Ethereum Signed Message:\n"+m.length),all=new Uint8Array(pre.length+m.length);
  all.set(pre);all.set(m,pre.length);
  const h=toHex(keccak256(all)),s=sig.replace(/^0x/,"");
  if(!/^[0-9a-fA-F]{130}$/.test(s))throw new Error("sig");
  let v=parseInt(s.slice(128,130),16);if(v<27)v+=27;if(v!==27&&v!==28)throw new Error("v");
  const data="0x"+h+v.toString(16).padStart(64,"0")+s.slice(0,64)+s.slice(64,128);
  const rr=await upstreamCall(env,JSON.stringify({jsonrpc:"2.0",id:1,method:"eth_call",params:[{to:"0x0000000000000000000000000000000000000001",data},"latest"]}));
  if(!rr)throw new Error("rpc");
  const j=JSON.parse(rr[1]);const out=(j.result||"").replace(/^0x/,"");
  if(out.length!==64||/^0+$/.test(out))throw new Error("recover");
  return "0x"+out.slice(24);
}
async function putDel(req,env){
  let b;try{b=await req.json()}catch(e){return J({error:"json"},400)}
  const action=b.action,token=String(b.token||""),ts=Number(b.ts);
  if(action!=="put"&&action!=="delete")return J({error:"action"},400);
  if(!ADDR_RE.test(token))return J({error:"token"},400);
  if(!(Math.abs(Date.now()/1000-ts)<300))return J({error:"time"},401);
  let png=null,sha="-";
  if(action==="put"){
    if(typeof b.png!=="string"||b.png.length>90000)return J({error:"size"},413);
    try{png=b64d(b.png)}catch(e){return J({error:"b64"},400)}
    if(png.length<80||png.length>MAXPNG)return J({error:"size"},413);
    const magic=[137,80,78,71,13,10,26,10];if(!magic.every((x,i)=>png[i]===x))return J({error:"png"},415);
    sha=await sha256hex(png);
  }
  let who;try{who=(await recoverSigner(env,msgFor(action,token,sha,ts),String(b.sig||""))).toLowerCase()}catch(e){return J({error:"sig"},401)}
  const admins=String(env.LOGO_ADMINS||"").toLowerCase().split(",").map(x=>x.trim()).filter(Boolean);
  if(!admins.includes(who))return J({error:"not-admin",who,listed:admins.length},403);
  const key="logo:"+token.toLowerCase();
  if(action==="put")await env.LOGOS.put(key,png,{metadata:{ts:Math.floor(Date.now()/1000),by:who,sha}});else await env.LOGOS.delete(key);
  return J({ok:true,action,token:token.toLowerCase()});
}
/* Official Polygon tokens (checked on-chain). Logos for THESE addresses only are fetched from public asset repos by ADDRESS (never by name/symbol), then cached.
   A logo uploaded from /admin (KV) always wins. Any other address: 404 -> the site shows letters + risk notice. */
const OFFICIAL_LOGOS={"0xc2132d05d31c914a87c6611c10748aeb04b58e8f":"0xc2132D05D31c914a87C6611C10748AEb04B58e8F","0x7ceb23fd6bc0add59e62ac25578270cff1b9f619":"0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619","0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6":"0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6","0x8f3cf7ad23cd3cadbd9735aff958023239c6a063":"0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063","0xd6df932a45c0f255f85145f286ea0b292b21c90b":"0xD6DF932A45C0f255f85145f286eA0b292B21C90B","0xb0897686c545045afc77cf20ec7a532e3120e0f1":"0xb0897686c545045aFc77CF20eC7A532E3120E0F1","0xb33eaad8d922b1083446dc23f610c2567fb5180f":"0xb33EaAd8d922B1083446DC23f610c2567fB5180f","0x2791bca1f2de4661ed88a30c99a7a9449aa84174":"0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174","0xbbba073c31bf03b8acf7c28ef0738decf3695683":"0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683","0xa1c57f48f0deb89f569dfbe6e2b7f46d33606fd4":"0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4","0x5fe2b58c013d7601147dcdd68c143a77499f5531":"0x5fe2B58c013d7601147DcdD68C143A77499f5531","0x172370d5cd63279efa6d502dab29171933a610af":"0x172370d5Cd63279eFa6d502DAB29171933a610AF","0xb5c064f955d8e7f38fe0460c556a72987494ee17":"0xB5C064F955D8e7F38fE0460C556a72987494eE17","0x0b3f868e0be5597d5db7feb59e1cadbb0fdda50a":"0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a","0xc3c7d422809852031b44ab29eec9f1eff2a58756":"0xC3C7d422809852031b44ab29EEC9F1EfF2A58756","0x9c2c5fd7b07e95ee044ddeba0e97a665f142394f":"0x9c2C5fd7b07E95EE044DDeba0E97a665F142394f"};
const LOGO_SRC=a=>["https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/polygon/assets/"+a+"/logo.png","https://raw.githubusercontent.com/Uniswap/assets/master/blockchains/polygon/assets/"+a+"/logo.png"];
const PNG_MAGIC=[0x89,0x50,0x4e,0x47];
const logoHeaders=()=>({"content-type":"image/png","cache-control":"public,max-age=900","x-content-type-options":"nosniff","content-security-policy":"default-src 'none'","cross-origin-resource-policy":"same-origin"});
async function officialLogo(addr,ctx){
  const cs=OFFICIAL_LOGOS[addr.toLowerCase()];if(!cs)return null;
  const ck=new Request("https://logo-cache.invalid/"+cs);
  try{const hit=await caches.default.match(ck);if(hit)return hit.arrayBuffer()}catch(e){}
  for(const url of LOGO_SRC(cs)){
    try{
      const r=await fetch(url,{cf:{cacheTtl:86400,cacheEverything:true}});
      if(!r.ok)continue;
      const b=await r.arrayBuffer();
      if(b.byteLength<80||b.byteLength>250000)continue;
      const u=new Uint8Array(b);if(!PNG_MAGIC.every((x,i)=>u[i]===x))continue;
      try{const put=caches.default.put(ck,new Response(b,{headers:{"content-type":"image/png","cache-control":"public,max-age=604800"}}));ctx&&ctx.waitUntil?ctx.waitUntil(put):await put}catch(e){}
      return b;
    }catch(e){}
  }
  return null;
}
async function getLogo(env,addr,ctx){
  if(!ADDR_RE.test(addr))return new Response("not found",{status:404});
  let v=await env.LOGOS.get("logo:"+addr.toLowerCase(),{type:"arrayBuffer"});
  if(!v)v=await officialLogo(addr,ctx);
  if(!v)return new Response("not found",{status:404,headers:{"cache-control":"public,max-age=60"}});
  return new Response(v,{headers:logoHeaders()});
}
export default{
  async fetch(req,env,ctx){
    const u=new URL(req.url);
    if(u.pathname.startsWith("/logo/")&&req.method==="GET")return getLogo(env,u.pathname.slice(6),ctx);
    if(u.pathname==="/api/logo"&&req.method==="POST")return putDel(req,env);
    if(u.pathname==="/rpc"&&req.method==="POST")return rpcProxy(req,env,u);
    const res=await env.ASSETS.fetch(req);
    const h=new Headers(res.headers);
    const adm=u.pathname==="/admin"||u.pathname.startsWith("/admin/")||u.pathname==="/admin.html";
    h.set("content-security-policy",adm?CSP_ADMIN:CSP_SITE);
    return new Response(res.body,{status:res.status,statusText:res.statusText,headers:h});
  }
};
