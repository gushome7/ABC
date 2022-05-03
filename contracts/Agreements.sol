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
        uint256 validblock;
    }

    mapping(address => agreement) private _agreements;
    mapping(uint256 => address) public agreementTokens;
    address[] private _idagreements;

    uint256 public agreementMinted=0;
    uint256 public agreementUsed=0;

    uint256 public constant blocksDelay=63600;

    constructor() {
        _idagreements.push(address(0)); //To get all real agreements over 0 index
    }

    /* @dev: Devuelve un array con todas las direcciones de titulares de acuerdos
    */
    function getList() public view returns(address[] memory) {
        return(_idagreements);
    }

    /* Devuelve los datos del agreement con el titular de la direccion indicada en address
     * Parametros:
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
        if(_agreements[_address].active && block.number > _agreements[_address].validblock ) {
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

    function updateAgreementBalance(uint256 _amount, uint256 _tokens) internal {
        require(_agreements[_msgSender()].active,"Agreement not yet active");
        require(block.number > _agreements[_msgSender()].validblock, "Must wait for a valid block");
        require(_agreements[_msgSender()].credits-_agreements[_msgSender()].used >= _amount,"Not enough available credit");
        _agreements[_msgSender()].used=_agreements[_msgSender()].used+_amount;
        agreementUsed=agreementUsed+_amount;
        agreementMinted=agreementMinted+_tokens;
    }

    /* @dev: Mantiene una lista de los Ids de tokens.
     * La lista se utiliza para excluirlos de los derechos politicos de la DAO solo reservados para los titulares de
     * tokens emitidos regularmente. 
     */
    function updateTokensMinted(uint256 _tokenId) internal {
        agreementTokens[_tokenId]=_msgSender();
    }

    /* @dev Crea un acuerdo inactivo. ABC Starter es por ahora el owner de la opcion de crear agreements
     * aunque no de activarlos. 
     * @params:
     * name: identification of the agreement
     * description: a brief description
     * credits: amount to be assigned
     * activator: address authorized to activate agreement
     * address: if active, from what address can mint using credit.
     * El agreement no puede ser activado antes del bloque establecido en ValidBlock. Esto da a la comunidad un time frame para
     * reaccionar en caso de un acuerdo creado en forma espurea.
     */

    function createAgreement(string memory _name, string memory _description, uint256 _credits, address _activator, address _address) public onlyOwner {
        agreement memory _agreement;
        _agreement.id=_idagreements.length;
        _agreement.name=_name;
        _agreement.description=_description;
        _agreement.credits=_credits;
        _agreement.active=false;
        _agreement.activator=_activator;
        _agreement.validblock=block.number+blocksDelay;
        _idagreements.push(_address);
        _agreements[_address]=_agreement;
    }

    /* @dev: Esta funcion debe ser llamada por el contrato de la DAO donde se someta a votacion el agreement
     * Los agreements los crea el owner del contrato (ABCStarter al menos inicialmente), pero ningun agreement
     * es efectivo hasta que sea sometido a votacion de los miemnbros del Club.
     * El contrato de votacion debe incluir una llamada a esta funcion una vez que se verifica el resultado 
     * exitoso de la votacion. Mientras eso no ocurra, el acuerdo no esta activo por lo que no se mintearan NFT
     * de la reserva estrategica referenciando al mismo.
     * El agreement tiene un delay de blocksDelay antes de ser valido. Esto da a la comunidad un time frame para
     * reaccionar en caso de un acuerdo activado en forma espurea.
     */
    function activateAgreement(uint256 _id) public {
        require(_idagreements[_id] != address(0), "Agreement not found");
        address _agreement=_idagreements[_id];
        require(_agreements[_agreement].id >0, "Invalid agreement");
        require(_agreements[_agreement].activator == _msgSender(),"Only activator can activate agreement");
        require(block.number > _agreements[_agreement].validblock,"Wait for valid block until activate");
        require(_agreements[_agreement].active==false,"Agreement already active");
        _agreements[_agreement].active=true;
        _agreements[_agreement].validblock=block.number+blocksDelay;
    }

}    