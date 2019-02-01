pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "./abstract/BallotEnums.sol";
import "./abstract/EnvConstants.sol";
import "./interface/IBallotStorage.sol";
import "./interface/IEnvStorage.sol";
import "./Gov.sol";
import "./Staking.sol";


contract GovImp is Gov, ReentrancyGuard, BallotEnums, EnvConstants {
    using SafeMath for uint256;

    event MemberAdded(address indexed addr);
    event MemberRemoved(address indexed addr);
    event MemberChanged(address indexed oldAddr, address indexed newAddr);
    event EnvChanged(bytes32 envName, uint256 envType, bytes envVal);

    function addProposalToAddMember(
        address member,
        bytes enode,
        bytes ip,
        uint port,
        uint256 lockAmount
    )
        external
        onlyGovMem
        nonReentrant
        returns (uint256 ballotIdx)
    {
        require(msg.sender != member, "Cannot add self");
        require(!isMember(member), "Already member");

        ballotIdx = ballotLength.add(1);
        createBallotForMemeber(
            ballotIdx, // ballot id
            uint256(BallotTypes.MemberAdd), // ballot type
            msg.sender, // creator
            address(0), // old member address
            member, // new member address
            enode, // new enode
            ip, // new ip
            port // new port
        );
        updateBallotLock(ballotIdx, lockAmount);
        ballotLength = ballotIdx;
    }

    function addProposalToRemoveMember(
        address member,
        uint256 lockAmount
    )
        external
        onlyGovMem
        nonReentrant
        returns (uint256 ballotIdx)
    {
        require(isMember(member), "Non-member");
        require(getMemberLength() > 1, "Cannot remove a sole member");

        ballotIdx = ballotLength.add(1);
        createBallotForMemeber(
            ballotIdx, // ballot id
            uint256(BallotTypes.MemberRemoval), // ballot type
            msg.sender, // creator
            member, // old member address
            address(0), // new member address
            new bytes(0), // new enode
            new bytes(0), // new ip
            0 // new port
        );
        updateBallotLock(ballotIdx, lockAmount);
        ballotLength = ballotIdx;
    }

    function addProposalToChangeMember(
        address target,
        address nMember,
        bytes nEnode,
        bytes nIp,
        uint nPort,
        uint256 lockAmount
    )
        external
        onlyGovMem
        nonReentrant
        returns (uint256 ballotIdx)
    {
        require(isMember(target), "Non-member");

        ballotIdx = ballotLength.add(1);
        createBallotForMemeber(
            ballotIdx, // ballot id
            uint256(BallotTypes.MemberChange), // ballot type
            msg.sender, // creator
            target, // old member address
            nMember, // new member address
            nEnode, // new enode
            nIp, // new ip
            nPort // new port
        );
        updateBallotLock(ballotIdx, lockAmount);
        ballotLength = ballotIdx;
    }

    function addProposalToChangeGov(
        address newGovAddr
    )
        external
        onlyGovMem
        nonReentrant
        returns (uint256 ballotIdx)
    {
        require(newGovAddr != address(0), "Implementation cannot be zero");
        require(newGovAddr != implementation(), "Same contract address");

        ballotIdx = ballotLength.add(1);
        IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).createBallotForAddress(
            ballotLength.add(1), // ballot id
            uint256(BallotTypes.GovernanceChange), // ballot type
            msg.sender, // creator
            newGovAddr // new governance address
        );
        ballotLength = ballotIdx;
    }

    function addProposalToChangeEnv(
        bytes32 envName,
        uint256 envType,
        bytes envVal
    )
        external
        onlyGovMem
        nonReentrant
        returns (uint256 ballotIdx)
    {
        require(uint256(VariableTypes.Int) <= envType && envType <= uint256(VariableTypes.String), "Invalid type");

        ballotIdx = ballotLength.add(1);
        IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).createBallotForVariable(
            ballotIdx, // ballot id
            uint256(BallotTypes.EnvValChange), // ballot type
            msg.sender, // creator
            envName, // env name
            envType, // env type
            envVal // env value
        );
        ballotLength = ballotIdx;
    }

    function vote(uint256 ballotIdx, bool approval) external onlyGovMem nonReentrant {
        address ballotStorage = getContractAddress(BALLOT_STORAGE_NAME);
        // Check if some ballot is in progress
        if (ballotInVoting != 0) {
            (uint256 ballotType, uint256 state, ) = getBallotState(ballotInVoting);
            (, uint256 endTime, ) = getBallotPeriod(ballotInVoting);
            if (state == uint256(BallotStates.InProgress)) {
                if (endTime < block.timestamp) {
                    finalizeBallot(ballotIdx, uint256(BallotStates.Rejected));
                    ballotInVoting = 0;
                    if (ballotIdx == ballotInVoting) {
                        return;
                    }
                } else if (ballotIdx != ballotInVoting) {
                    revert("Now in voting with different ballot");
                }
            }
        }

        // Check if the ballot can be voted
        (ballotType, state, ) = getBallotState(ballotIdx);
        if (state == uint256(BallotStates.Ready)) {
            (, , uint256 duration) = getBallotPeriod(ballotIdx);
            if (duration < getMinVotingDuration()) {
                startBallot(ballotIdx, block.timestamp, block.timestamp + getMinVotingDuration());
            } else if (getMaxVotingDuration() < duration) {
                startBallot(ballotIdx, block.timestamp, block.timestamp + getMaxVotingDuration());
            } else {
                startBallot(ballotIdx, block.timestamp, block.timestamp + duration);
            }
            ballotInVoting = ballotIdx;
        } else if (state == uint256(BallotStates.InProgress)) {
            // Nothing to do
        } else {
            revert("Expired");
        }

        // Vote
        uint256 voteIdx = voteLength.add(1);
        if (approval) {
            IBallotStorage(ballotStorage).createVote(
                voteIdx,
                ballotIdx,
                msg.sender,
                uint256(DecisionTypes.Accept),
                Staking(getContractAddress(STAKING_NAME)).calcVotingWeight(msg.sender)
            );
        } else {
            IBallotStorage(ballotStorage).createVote(
                voteIdx,
                ballotIdx,
                msg.sender,
                uint256(DecisionTypes.Reject),
                Staking(getContractAddress(STAKING_NAME)).calcVotingWeight(msg.sender)
            );
        }
        voteLength = voteIdx;

        // Finalize
        (, uint256 accept, uint256 reject) = getBallotVotingInfo(ballotIdx);
        if (accept.add(reject) < getThreshould()) {
            return;
        }
        if (accept > reject) {
            if (ballotType == uint256(BallotTypes.MemberAdd)) {
                addMember(ballotIdx);
            } else if (ballotType == uint256(BallotTypes.MemberRemoval)) {
                removeMember(ballotIdx);
            } else if (ballotType == uint256(BallotTypes.MemberChange)) {
                changeMember(ballotIdx);
            } else if (ballotType == uint256(BallotTypes.GovernanceChange)) {
                if (IBallotStorage(ballotStorage).getBallotAddress(ballotIdx) != address(0)) {
                    setImplementation(IBallotStorage(ballotStorage).getBallotAddress(ballotIdx));
                }
            } else if (ballotType == uint256(BallotTypes.EnvValChange)) {
                applyEnv(ballotIdx);
            }
            finalizeBallot(ballotIdx, uint256(BallotStates.Accepted));
        } else {
            finalizeBallot(ballotIdx, uint256(BallotStates.Rejected));
        }
        ballotInVoting = 0;
    }

    // FIXME: get from EnvStorage
    function getMinStaking() public pure returns (uint256) { return 10 ether; }

    function getMaxStaking() public pure returns (uint256) { return 100 ether; }

    function getMinVotingDuration() public pure returns (uint256) { return 1 days; }
    
    function getMaxVotingDuration() public pure returns (uint256) { return 7 days; }

    function getThreshould() public pure returns (uint256) { return 51; } // 51% from 51 of 100

    function addMember(uint256 ballotIdx) private {
        (uint256 ballotType, uint256 state, ) = getBallotState(ballotIdx);
        require(ballotType == uint256(BallotTypes.MemberAdd), "Not voting for addMember");
        require(state == uint(BallotStates.InProgress), "Invalid voting state");
        (, uint256 accept, uint256 reject) = getBallotVotingInfo(ballotIdx);
        require(accept.add(reject) >= getThreshould(), "Not yet finalized");

        (
            , address addr,
            bytes memory enode,
            bytes memory ip,
            uint port,
            uint256 lockAmount
        ) = getBallotMember(ballotIdx);
        if (isMember(addr)) {
            return; // Already member. it is abnormal case
        }

        // Lock
        require(getMinStaking() <= lockAmount && lockAmount <= getMaxStaking(), "Invalid lock amount");
        lock(addr, lockAmount);

        // Add member
        uint256 nMemIdx = memberLength.add(1);
        members[nMemIdx] = addr;
        memberIdx[addr] = nMemIdx;

        // Add node
        uint256 nNodeIdx = nodeLength.add(1);
        Node storage node = nodes[nNodeIdx];
        node.enode = enode;
        node.ip = ip;
        node.port = port;
        nodeIdxFromMember[addr] = nNodeIdx;
        nodeToMember[nNodeIdx] = addr;

        memberLength = nMemIdx;
        nodeLength = nNodeIdx;

        emit MemberAdded(addr);
    }

    function removeMember(uint256 ballotIdx) private {
        (uint256 ballotType, uint256 state, ) = getBallotState(ballotIdx);
        require(ballotType == uint256(BallotTypes.MemberRemoval), "Not voting for removeMember");
        require(state == uint(BallotStates.InProgress), "Invalid voting state");
        (, uint256 accept, uint256 reject) = getBallotVotingInfo(ballotIdx);
        require(accept.add(reject) >= getThreshould(), "Not yet finalized");

        (address addr, , , , , uint256 unlockAmount) = getBallotMember(ballotIdx);
        if (!isMember(addr)) {
            return; // Non-member. it is abnormal case
        }

        // Remove member
        if (memberIdx[addr] != memberLength) {
            (members[memberIdx[addr]], members[memberLength]) = (members[memberLength], members[memberIdx[addr]]);
        }
        memberIdx[addr] = 0;
        members[memberLength] = address(0);
        memberLength = memberLength.sub(1);

        // Remove node
        if (nodeIdxFromMember[addr] != nodeLength) {
            Node storage node = nodes[nodeIdxFromMember[addr]];
            node.enode = nodes[nodeLength].enode;
            node.ip = nodes[nodeLength].ip;
            node.port = nodes[nodeLength].port;
        }
        nodeIdxFromMember[addr] = 0;
        nodeToMember[nodeLength] = address(0);
        nodeLength = nodeLength.sub(1);

        // Unlock
        unlock(addr, unlockAmount);

        emit MemberRemoved(addr);
    }

    function changeMember(uint256 ballotIdx) private {
        (uint256 ballotType, uint256 state, ) = getBallotState(ballotIdx);
        require(ballotType == uint256(BallotTypes.MemberChange), "Not voting for changeMember");
        require(state == uint(BallotStates.InProgress), "Invalid voting state");
        (, uint256 accept, uint256 reject) = getBallotVotingInfo(ballotIdx);
        require(accept.add(reject) >= getThreshould(), "Not yet finalized");
        
        (
            address addr,
            address nAddr,
            bytes memory enode,
            bytes memory ip,
            uint port,
            uint256 lockAmount
        ) = getBallotMember(ballotIdx);
        if (!isMember(addr)) {
            return; // Non-member. it is abnormal case
        }

        if (addr != nAddr) {
            // Lock
            require(getMinStaking() <= lockAmount && lockAmount <= getMaxStaking(), "Invalid lock amount");
            lock(nAddr, lockAmount);
            // Change member
            members[memberIdx[addr]] = nAddr;
        }

        // Change node
        uint256 nodeIdx = nodeIdxFromMember[addr];
        Node storage node = nodes[nodeIdx];
        node.enode = enode;
        node.ip = ip;
        node.port = port;
        if (addr != nAddr) {
            nodeToMember[nodeIdx] = nAddr;
            nodeIdxFromMember[nAddr] = nodeIdx;
            nodeIdxFromMember[addr] = 0;
            // Unlock
            unlock(addr, lockAmount);

            emit MemberChanged(addr, nAddr);
        }
    }

    function applyEnv(uint256 ballotIdx) private {
        (uint256 ballotType, uint256 state, ) = getBallotState(ballotIdx);
        require(ballotType == uint256(BallotTypes.EnvValChange), "Not voting for applyEnv");
        require(state == uint(BallotStates.InProgress), "Invalid voting state");

        (
            bytes32 envKey,
            uint256 envType,
            bytes memory envVal
        ) = IBallotStorage(getContractAddress(ENV_STORAGE_NAME)).getBallotVariable(ballotIdx);

        IEnvStorage envStorage = IEnvStorage(getContractAddress(ENV_STORAGE_NAME));
        if (envKey == BLOCK_PER_NAME && envType == BLOCK_PER_TYPE) {
            envStorage.setBlockPerByBytes(envVal);
        } else if (envKey == BALLOT_DURATION_MIN_NAME && envType == BALLOT_DURATION_MIN_TYPE) {
            envStorage.setBallotDurationMinByBytes(envVal);
        } else if (envKey == BALLOT_DURATION_MAX_NAME && envType == BALLOT_DURATION_MAX_TYPE) {
            envStorage.setBallotDurationMaxByBytes(envVal);
        } else if (envKey == STAKING_MIN_NAME && envType == STAKING_MIN_TYPE) {
            envStorage.setStakingMinByBytes(envVal);
        } else if (envKey == STAKING_MAX_NAME && envType == STAKING_MAX_TYPE) {
            envStorage.setStakingMaxByBytes(envVal);
        }

        emit EnvChanged(envKey, envType, envVal);
    }

    //------------------ Code reduction
    function createBallotForMemeber(
        uint256 id,
        uint256 bType,
        address creator,
        address oAddr,
        address nAddr,
        bytes enode,
        bytes ip,
        uint port
    )
        private
    {
        IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).createBallotForMemeber(
            id, // ballot id
            bType, // ballot type
            creator, // creator
            oAddr, // old member address
            nAddr, // new member address
            enode, // new enode
            ip, // new ip
            port // new port
        );
    }

    function updateBallotLock(uint256 id, uint256 amount) private {
        IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).updateBallotMemberLockAmount(id, amount);
    }

    function startBallot(uint256 id, uint256 s, uint256 e) private {
        IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).startBallot(id, s, e);
    }

    function finalizeBallot(uint256 id, uint256 state) private {
        IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).finalizeBallot(id, state);
    }

    function getBallotState(uint256 id) private view returns (uint256, uint256, bool) {
        return IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).getBallotState(id);
    }

    function getBallotPeriod(uint256 id) private view returns (uint256, uint256, uint256) {
        return IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).getBallotPeriod(id);
    }

    function getBallotVotingInfo(uint256 id) private view returns (uint256, uint256, uint256) {
        return IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).getBallotVotingInfo(id);
    }

    function getBallotMember(uint256 id) private view returns (address, address, bytes, bytes, uint256, uint256) {
        return IBallotStorage(getContractAddress(BALLOT_STORAGE_NAME)).getBallotMember(id);
    }

    function lock(address addr, uint256 amount) private {
        Staking(getContractAddress(STAKING_NAME)).lock(addr, amount);
    }

    function unlock(address addr, uint256 amount) private {
        Staking(getContractAddress(STAKING_NAME)).unlock(addr, amount);
    }
    //------------------ Code reduction end
}