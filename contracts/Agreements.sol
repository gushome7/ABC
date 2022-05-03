// SPDX-License-Identifier: MIT
/*
 * @title: Asteroid Belt Club NFT Strategic Agreements
 * @author: Gustavo Hernandez Baratta  (The Pan de Azucar Bay Company LLC)
 * Extension de Acuerdos Estrategicos del ABC.
 * 
 
 * email: ghernandez@pandeazucarbay.com
 */

pragma solidity ^0.8.1;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

abstract contract Agreements is Ownable {

    struct agreement {
        uint256 id;
        string name;
        string description;
        uint256 credits;
        uint256 used;
        bool active;
        address activator;
    }

    mapping(address => agreement) private _agreements;
    address[] private _idagreements;

    uint256 public agreementMinted=0;
    uint256 public agreementCount=0;

    constructor() {
        _idagreements.push(address(0)); //To get all real agreements over 0 index
    }

    /* @dev: Devuelve un array con todas las direcciones de titulares de acuerdos
    */
    function getList() public view returns(address[] memory) {
        return(_idagreements);
    }

    /* Devuelve los datos del agreement con el titular de la direccion indicada en address
     * Parametros>
     * _address: direccion del titular del acuerdo.
     */
    function getAgreement(address _address) public view returns(agreement memory) {
        return(_agreements[_address]);
    }

    /* @dev: permite consultar el credito disponible del acuerdo para mintear tokens 
     * Params:
     * address: la direccion del titular del acuerdo.
     */
    function getAgreementBalance(address _address) public view returns(uint256) {
        if(_agreements[_address].active) {
            return _agreements[_address].credits - _agreements[_address].used;
        }
        return(0);
    }

    /* @dev: actualiza el saldo disponible para mintear tokens, restando el costo del o de los tokens minteados
     * La funcion mint la llama el titular del credito disponible, por lo que es su cuenta la que se reduce en el
     * costo de lo minteado.
     * Params:
     * _addused: costo de los nft minteados
     * _count: cantidad de tokens minteados.
     */

    function updateAgreementBalance(uint256 _addused, uint256 _count) public {
        require(_agreements[_msgSender()].active,"Agreement not yet active");
        require(_agreements[_msgSender()].credits-_agreements[_msgSender()].used >= _addused,"Not enough available credit");
        _agreements[_msgSender()].used=_agreements[_msgSender()].used+_addused;
        agreementMinted=agreementMinted+_addused;
        agreementCount=agreementCount+_count;
    }

    /* @dev Crea un acuerdo inactivo. ABC Starter es por ahora el owner de la opcion de crear agreements
     * aunque no de activarlos. 
     * @params:
     * name: identification of the agreement
     * description: a brief description
     * credits: amount to be assigned
     * activator: address authorized to activate agreement
     * address: if active, from what address can mint using credit.

    */

    function createAgreement(string memory _name, string memory _description, uint256 _credits, address _activator, address _address) public onlyOwner {
        agreement memory _agreement;
        _agreement.id=_idagreements.length;
        _agreement.name=_name;
        _agreement.description=_description;
        _agreement.credits=_credits;
        _agreement.active=false;
        _agreement.activator=_activator;

        _idagreements.push(_address);
        _agreements[_address]=_agreement;
    }

    /* @dev: Esta funcion debe ser llamada por el contrato de la DAO donde se someta a votacion el agreement
     * Los agreements los crea el owner del contrato (ABCStarter al menos inicialmente), pero ningun agreement
     * es efectivo hasta que sea sometido a votacion de los miemnbros del Club.
     * El contrato de votacion debe incluir una llamada a esta funcion una vez que se verifica el resultado 
     * exitoso de la votacion. Mientras eso no ocurra, el acuerdo no esta activo por lo que no se mintearan NFT
     * de la reserva estrategica referenciando al mismo.
     */
    function activateAgreement(uint256 _id) public {
        require(_idagreements[_id] != address(0), "Agreement not found");
        address _agreement=_idagreements[_id];
        require(_agreements[_agreement].id >0);
        require(_agreements[_agreement].activator == _msgSender(),"Only activator can activate agreement");
        require(_agreements[_agreement].active==false,"Agreement already active");
        _agreements[_agreement].active=true;
    }

}    