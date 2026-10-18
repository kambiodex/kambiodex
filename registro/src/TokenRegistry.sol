// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title KAMBIODEX Token Registry
/// @notice Lista simples e pública de tokens: 0 = sem decisão, 1 = na lista da KAMBIODEX, 2 = bloqueado.
/// @dev Só o dono escreve. Não guarda dinheiro, não chama outros contratos e não tem poder sobre
///      pools, Factory ou Router: o site apenas LÊ esta lista para decidir o que mostrar.
///      Na mainnet o dono deve ser a Safe (multisig). Troca de dono em duas etapas.
contract TokenRegistry {
    uint8 public constant NONE = 0;
    uint8 public constant LISTED = 1;
    uint8 public constant BLOCKED = 2;

    address public owner;
    address public pendingOwner;

    mapping(address => uint8) private _status;
    mapping(address => bool) private _known;
    address[] private _tokens;

    event StatusSet(address indexed token, uint8 status);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error NotPendingOwner();
    error BadStatus();
    error ZeroAddress();
    error LengthMismatch();
    error TooMany();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    // ---------------- escrita (só o dono) ----------------

    function setStatus(address token, uint8 status) external onlyOwner {
        _set(token, status);
    }

    function setStatusBatch(address[] calldata tokens, uint8[] calldata statuses_) external onlyOwner {
        if (tokens.length != statuses_.length) revert LengthMismatch();
        if (tokens.length > 200) revert TooMany();
        for (uint256 i = 0; i < tokens.length; i++) {
            _set(tokens[i], statuses_[i]);
        }
    }

    function _set(address token, uint8 status) private {
        if (token == address(0)) revert ZeroAddress();
        if (status > BLOCKED) revert BadStatus();
        if (!_known[token]) {
            _known[token] = true;
            _tokens.push(token);
        }
        _status[token] = status;
        emit StatusSet(token, status);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    // ---------------- leitura (qualquer pessoa) ----------------

    function statusOf(address token) external view returns (uint8) {
        return _status[token];
    }

    function statuses(address[] calldata tokens) external view returns (uint8[] memory out) {
        out = new uint8[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            out[i] = _status[tokens[i]];
        }
    }

    function count() external view returns (uint256) {
        return _tokens.length;
    }

    /// @notice Devolve até `n` tokens a partir da posição `start`, com o estado de cada um.
    function page(uint256 start, uint256 n) external view returns (address[] memory toks, uint8[] memory sts) {
        uint256 total = _tokens.length;
        if (start >= total) return (new address[](0), new uint8[](0));
        uint256 end = start + n;
        if (end > total) end = total;
        toks = new address[](end - start);
        sts = new uint8[](end - start);
        for (uint256 i = start; i < end; i++) {
            toks[i - start] = _tokens[i];
            sts[i - start] = _status[_tokens[i]];
        }
    }
}
