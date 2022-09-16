
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

contract Notary is Ownable {
    uint256 _idsettlement=1;
    /* settlement structure */ 
    struct settlement {
        uint256 id; //sequence
        string hash; //sha256 to protocolize
        address claimant; //address of petitioner
        uint256 blocknum; //protocolized at block number
        uint256 blocktime; //protocolized at block time
    }
    mapping(address => bool) private _allowed; //who can use Notary Service
    mapping(uint256 => settlement) private _settled; // stored settled
    mapping(string => uint256) private _settledidx; //settledidx


    
    event NewSettlement(uint256 id, string hash);

    constructor() {
        _allowed[msg.sender]=true;
    }

    modifier onlyAllowed() {
        require(_allowed[msg.sender]==true, 'Not allowed');
        _;
    }

   function allow(address _to) public onlyOwner {
        _allowed[_to]=true;
    }
    function disallow(address _to) public onlyOwner {
        _allowed[_to]=false;
    }

    function settle( string memory _hash) public onlyAllowed returns(uint256) {
        require(_settledidx[_hash]==0, "Already settled");
        settlement memory __settlement;
        __settlement.id = _idsettlement;
        __settlement.hash = _hash;
        __settlement.claimant=msg.sender;
        __settlement.blocknum=block.number;
        __settlement.blocktime=block.timestamp;
        _settled[__settlement.id]=__settlement;
        _settledidx[_hash]=__settlement.id;
        _idsettlement++;
        emit NewSettlement(__settlement.id,_hash);
        return(__settlement.id);
    }

    function getsettle(uint256 _id) public view returns(settlement memory) {
        require(_settled[_id].id==_id, "Settle not found");
        return(_settled[_id]);
    }

    function findsettle(string memory _hash) public view returns(settlement memory) {
        require(_settledidx[_hash]>0, "Not yet settled");
        return(_settled[_settledidx[_hash]]);
    }

}