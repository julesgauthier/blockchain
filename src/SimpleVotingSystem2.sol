// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {
    AccessControl
} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract SimpleVotingSystem is Ownable, AccessControl, ERC721 {
    struct Candidate {
        uint id;
        string name;
        uint voteCount;
    }
    enum Phase {
        None,
        Enregistrement, // Phase 1
        Donation, // Phase 2
        Vote, // Phase 3
        Depouillement // Phase 4
    }
    enum PhaseToken {
        Vote,
        Donation
    }
    enum Genre {
        None,
        Homme,
        Femme
    }

    mapping(uint => Candidate) public candidates;
    mapping(address => bool) public voters;
    mapping(address => Genre) public voterGenre;
    uint[] private candidateIds;

    Phase public currentPhase;
    uint256 public lastPhaseEndTimestamp;

    uint256 private _nextTokenId;

    mapping(address => bool) public hasDonated;
    mapping(uint256 => PhaseToken) public phaseTokens;

    bytes32 public constant PHASE1_ADMIN = keccak256("PHASE1_ADMIN");
    bytes32 public constant PHASE2_ADMIN = keccak256("PHASE2_ADMIN");
    bytes32 public constant PHASE3_ADMIN = keccak256("PHASE3_ADMIN");
    bytes32 public constant PHASE4_ADMIN = keccak256("PHASE4_ADMIN");

    uint256 public votesHomme;
    uint256 public votesFemme;
    uint256 public votesTotal;

    error WrongPhase(Phase expected, Phase current);
    error TooEarlyToStartNextPhase();
    error AlreadyVoted();
    error InvalidCandidateId();

    event PhaseAdminSet(uint8 phaseNumber, address admin);
    event PhaseStarted(Phase phase);
    event PhaseEnded(Phase phase);
    event DonationReceived(address indexed donor, uint256 amount);
    event Voted(address indexed voter, uint indexed candidateId, Genre gender);

    constructor() Ownable(msg.sender) ERC721("VotingProof", "VOTE") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        currentPhase = Phase.Enregistrement;
    }

    modifier onlyPhase(Phase expected) {
        if (currentPhase != expected) {
            revert WrongPhase(expected, currentPhase);
        }
        _;
    }

    modifier onlyAfterOneHourFromLastPhase() {
        if (
            lastPhaseEndTimestamp != 0 &&
            block.timestamp < lastPhaseEndTimestamp + 1 hours
        ) {
            revert TooEarlyToStartNextPhase();
        }
        _;
    }

    modifier onlyPhase1AdminOrOwner() {
        require(
            hasRole(PHASE1_ADMIN, msg.sender) || msg.sender == owner(),
            "Not phase 1 admin or owner"
        );
        _;
    }

    modifier onlyPhase2AdminOrOwner() {
        require(
            hasRole(PHASE2_ADMIN, msg.sender) || msg.sender == owner(),
            "Not phase 2 admin or owner"
        );
        _;
    }

    modifier onlyPhase3AdminOrOwner() {
        require(
            hasRole(PHASE3_ADMIN, msg.sender) || msg.sender == owner(),
            "Not phase 3 admin or owner"
        );
        _;
    }

    modifier onlyPhase4AdminOrOwner() {
        require(
            hasRole(PHASE4_ADMIN, msg.sender) || msg.sender == owner(),
            "Not phase 4 admin or owner"
        );
        _;
    }

    function addCandidate(
        string memory _name
    ) public onlyPhase1AdminOrOwner onlyPhase(Phase.Enregistrement) {
        require(bytes(_name).length > 0, "Candidate name cannot be empty");
        uint candidateId = candidateIds.length + 1;
        candidates[candidateId] = Candidate(candidateId, _name, 0);
        candidateIds.push(candidateId);
    }

    function vote(
        uint _candidateId,
        Genre _genre
    ) public onlyPhase(Phase.Vote) {
        if (!voters[msg.sender]) {
            revert AlreadyVoted();
        }
        if (_candidateId == 0 || _candidateId > candidateIds.length) {
            revert InvalidCandidateId();
        }

        require(
            _genre == Genre.Homme || _genre == Genre.Femme,
            "Invalid gender"
        );

        voters[msg.sender] = true;
        voterGenre[msg.sender] = _genre;

        candidates[_candidateId].voteCount += 1;
        votesTotal += 1;

        if (_genre == Genre.Homme) {
            votesHomme += 1;
        } else if (_genre == Genre.Femme) {
            votesFemme += 1;
        }

        _mintProof(msg.sender, PhaseToken.Vote);

        emit Voted(msg.sender, _candidateId, _genre);
    }

    function getTotalVotes(uint _candidateId) public view returns (uint) {
        require(
            _candidateId > 0 && _candidateId <= candidateIds.length,
            "Invalid candidate ID"
        );
        return candidates[_candidateId].voteCount;
    }

    function getCandidatesCount() public view returns (uint) {
        return candidateIds.length;
    }

    // Optional: Function to get candidate details by ID
    function getCandidate(
        uint _candidateId
    ) public view returns (Candidate memory) {
        require(
            _candidateId > 0 && _candidateId <= candidateIds.length,
            "Invalid candidate ID"
        );
        return candidates[_candidateId];
    }

    function _mintProof(address to, PhaseToken phaseToken) internal {
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;
        _safeMint(to, tokenId);
        phaseTokens[tokenId] = phaseToken;
    }

    function donate() public payable onlyPhase(Phase.Donation) {
        require(msg.value > 0, "No donation sent");

        if (!hasDonated[msg.sender]) {
            hasDonated[msg.sender] = true;
            _mintProof(msg.sender, PhaseToken.Donation);
        }

        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "Transfer failed");

        emit DonationReceived(msg.sender, msg.value);
    }

    function getWinner()
        public
        view
        onlyPhase4AdminOrOwner
        onlyPhase(Phase.Depouillement)
        returns (Candidate memory)
    {
        require(candidateIds.length > 0, "No candidates");

        uint winningId = candidateIds[0];

        for (uint i = 1; i < candidateIds.length; i++) {
            uint currentId = candidateIds[i];
            if (
                candidates[currentId].voteCount >
                candidates[winningId].voteCount
            ) {
                winningId = currentId;
            }
        }

        return candidates[winningId];
    }

    function getLoser()
        public
        view
        onlyPhase4AdminOrOwner
        onlyPhase(Phase.Depouillement)
        returns (Candidate memory)
    {
        require(candidateIds.length > 0, "No Candidates");

        uint losingId = candidateIds[0];

        for (uint i = 1; i < candidateIds.length; i++) {
            uint currentId = candidateIds[i];
            if (
                candidates[losingId].voteCount < candidates[currentId].voteCount
            ) {
                losingId = currentId;
            }
        }

        return candidates[losingId];
    }

    function getGenreStats()
        public
        view
        returns (uint256 hommePercent, uint256 femmePercent)
    {
        if (votesTotal == 0) {
            return (0, 0);
        }

        hommePercent = (votesHomme * 100) / votesTotal;
        femmePercent = (votesFemme * 100) / votesTotal;
    }

    function setPhase1Admin(address admin) public onlyOwner {
        _grantRole(PHASE1_ADMIN, admin);
        emit PhaseAdminSet(1, admin);
    }

    function setPhase2Admin(address admin) public onlyOwner {
        _grantRole(PHASE2_ADMIN, admin);
        emit PhaseAdminSet(2, admin);
    }

    function setPhase3Admin(address admin) public onlyOwner {
        _grantRole(PHASE3_ADMIN, admin);
        emit PhaseAdminSet(3, admin);
    }

    function setPhase4Admin(address admin) public onlyOwner {
        _grantRole(PHASE4_ADMIN, admin);
        emit PhaseAdminSet(4, admin);
    }

    function startPhase1()
        public
        onlyPhase1AdminOrOwner
        onlyAfterOneHourFromLastPhase
    {
        currentPhase = Phase.Enregistrement;
        emit PhaseStarted(Phase.Enregistrement);
    }

    function endPhase1()
        public
        onlyPhase1AdminOrOwner
        onlyPhase(Phase.Enregistrement)
    {
        currentPhase = Phase.None;
        lastPhaseEndTimestamp = block.timestamp;
        emit PhaseEnded(Phase.Enregistrement);
    }

    function startPhase2()
        public
        onlyPhase2AdminOrOwner
        onlyAfterOneHourFromLastPhase
    {
        currentPhase = Phase.Donation;
        emit PhaseStarted(Phase.Donation);
    }

    function endPhase2()
        public
        onlyPhase2AdminOrOwner
        onlyPhase(Phase.Donation)
    {
        currentPhase = Phase.None;
        lastPhaseEndTimestamp = block.timestamp;
        emit PhaseEnded(Phase.Donation);
    }

    function startPhase3()
        public
        onlyPhase3AdminOrOwner
        onlyAfterOneHourFromLastPhase
    {
        currentPhase = Phase.Vote;
        emit PhaseStarted(Phase.Vote);
    }

    function endPhase3() public onlyPhase3AdminOrOwner onlyPhase(Phase.Vote) {
        currentPhase = Phase.None;
        lastPhaseEndTimestamp = block.timestamp;
        emit PhaseEnded(Phase.Vote);
    }

    function startPhase4()
        public
        onlyPhase4AdminOrOwner
        onlyAfterOneHourFromLastPhase
    {
        currentPhase = Phase.Depouillement;
        emit PhaseStarted(Phase.Depouillement);
    }

    function endPhase4()
        public
        onlyPhase4AdminOrOwner
        onlyPhase(Phase.Depouillement)
    {
        currentPhase = Phase.None;
        lastPhaseEndTimestamp = block.timestamp;
        emit PhaseEnded(Phase.Depouillement);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControl, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
