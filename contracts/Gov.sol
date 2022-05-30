pragma solidity ^0.8.0;

//import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "./proxy/UpgradeabilityProxy.sol";
// import "./interface/IStaking.sol";
import "./abstract/AGov.sol";
// import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import "hardhat/console.sol";

contract Gov is AGov, Proxy, ERC1967Upgrade {
    // "Metadium Governance"
    uint public magic = 0x4d6574616469756d20476f7665726e616e6365;
    bool private _initialized;

    struct InitConstructor{
        address addr;
        uint256 lockAmount;
        bytes name;
        bytes enode;
        bytes ip;
        uint port;
    }

    function implementation() external view returns(address){
        return _implementation();
    }
    /**
     * @dev Returns the current implementation address.
     */
    function _implementation() internal view virtual override returns (address impl) {
        return ERC1967Upgrade._getImplementation();
    }
    
    function init(
        address registry,
        address newImplementation,
        address staker,
        uint256 lockAmount,
        bytes memory name,
        bytes memory enode,
        bytes memory ip,
        uint port
    )
        public onlyOwner
    {
        require(_initialized == false, "Already initialized");
        require(lockAmount > 0, "lockAmount should be more then zero");
        setRegistry(registry);
        // _setImplementation(implementation);
        _upgradeToAndCallUUPS(newImplementation, new bytes(0), false);

        // Lock
        IStaking staking = IStaking(getStakingAddress());
        require(staking.availableBalanceOf(staker) >= lockAmount, "Insufficient staking");
        require(staking.isAllowed(msg.sender, staker), 'Staker is not allowed');
        staking.lock(staker, lockAmount);

        // Add voting member
        memberLength = 1;
        members[memberLength] = msg.sender;
        memberIdx[msg.sender] = memberLength;

        // Add reward member
        rewards[memberLength] = msg.sender;
        rewardIdx[msg.sender] = memberLength;

        stakers[memberLength] = staker;
        stakersIdx[staker] = memberLength;
        memberToStaker[msg.sender] = staker;

        // Add node
        nodeLength = 1;
        Node storage node = nodes[nodeLength];
        node.name = name;
        node.enode = enode;
        node.ip = ip;
        node.port = port;
        nodeIdxFromMember[msg.sender] = nodeLength;
        nodeToMember[nodeLength] = msg.sender;

        _initialized = true;
        modifiedBlock = block.number;
    }

    // function initOnce(
    //     address registry,
    //     address newImplementation,
    //     InitConstructor[] memory infos
    // )
    //     public onlyOwner
    // {
    //     require(_initialized == false, "Already initialized");

    //     setRegistry(registry);
    //     _upgradeTo(newImplementation);

    //     _initialized = true;
    //     modifiedBlock = block.number;

    //     // []{uint addr, bytes name, bytes enode, bytes ip, uint port}
    //     // 32 bytes, [32 bytes, <data>] * 3, 32 bytes
    //     address addr;
    //     // bytes memory name;
    //     // bytes memory enode;
    //     // bytes memory ip;
    //     // uint port;
    //     uint idx = 0;

    //     // uint ix;
    //     // uint eix;
    //     for(; idx<infos.length;idx++){
    //         // Lock
    //         IStaking staking = IStaking(getStakingAddress());
    //         require(staking.availableBalanceOf(msg.sender) >= infos[idx].lockAmount, "Insufficient staking");
    //         staking.lock(msg.sender, infos[idx].lockAmount);
    //         memberLength = idx+1;
    //         members[memberLength] = infos[idx].addr;
    //         memberIdx[addr] = memberLength;
    //         rewards[memberLength] = infos[idx].addr;
    //         rewardIdx[addr] = memberLength;
            
    //         nodeLength = memberLength;
    //         Node storage node = nodes[nodeLength];
    //         node.name = infos[idx].name;
    //         node.enode = infos[idx].enode;
    //         node.ip = infos[idx].ip;
    //         node.port = infos[idx].port;
    //         nodeToMember[nodeLength] = infos[idx].addr;
    //         nodeIdxFromMember[addr] = nodeLength;
    //     }
    //     // assembly {
    //     //     ix := add(data, 0x20)
    //     // }
    //     // eix = ix + data.length;
    //     // while (ix < eix) {
    //     //     assembly {
    //     //         addr := mload(ix)
    //     //     }
    //     //     // addr = address(port);
    //     //     ix += 0x20;
    //     //     require(ix < eix);

    //     //     assembly {
    //     //         name := ix
    //     //     }
    //     //     ix += 0x20 + name.length;
    //     //     require(ix < eix);

    //     //     assembly {
    //     //         enode := ix
    //     //     }
    //     //     ix += 0x20 + enode.length;
    //     //     require(ix < eix);

    //     //     assembly {
    //     //         ip := ix
    //     //     }
    //     //     ix += 0x20 + ip.length;
    //     //     require(ix < eix);

    //     //     assembly {
    //     //         port := mload(ix)
    //     //     }
    //     //     ix += 0x20;

    //     //     idx += 1;
    //     //     members[idx] = addr;
    //     //     memberIdx[addr] = idx;
    //     //     rewards[idx] = addr;
    //     //     rewardIdx[addr] = idx;

    //     //     Node storage node = nodes[idx];
    //     //     node.name = name;
    //     //     node.enode = enode;
    //     //     node.ip = ip;
    //     //     node.port = port;
    //     //     nodeToMember[idx] = addr;
    //     //     nodeIdxFromMember[addr] = idx;
    //     // }
    //     // memberLength = idx;
    //     // nodeLength = idx;
    // }
}
