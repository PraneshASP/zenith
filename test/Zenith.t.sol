// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Zenith} from "../src/Zenith.sol";

contract ZenithTest is Test {
    Zenith public target;

    Zenith.BlockHeader header;
    bytes32 commit;
    /// @dev blockData is ignored by the contract. it's included for the purpose of DA for the node.
    bytes blockData = "";

    uint256 sequencerKey = 123;
    uint256 notSequencerKey = 300;

    event BlockSubmitted(
        address indexed sequencer,
        uint256 indexed rollupChainId,
        uint256 gasLimit,
        address rewardAddress,
        bytes32 blockDataHash
    );

    function setUp() public {
        address[] memory initialEnterTokens;
        target = new Zenith(block.chainid + 1, address(this), initialEnterTokens, address(this));
        target.addSequencer(vm.addr(sequencerKey));

        // set default block values
        header.rollupChainId = block.chainid + 1;
        header.hostBlockNumber = block.number;
        header.gasLimit = 30_000_000;
        header.rewardAddress = address(this);
        header.blockDataHash = keccak256(blockData);

        // derive block commitment from the header
        commit = target.blockCommitment(header);
    }

    // cannot submit block with incorrect host block number
    function test_incorrectHostBlock() public {
        // change to incorrect host block number
        header.hostBlockNumber = 100;
        commit = target.blockCommitment(header);

        // sign block commitmenet with sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        vm.expectRevert(Zenith.IncorrectHostBlock.selector);
        target.submitBlock(header, v, r, s, blockData);
    }

    // can submit block successfully with acceptable header & correct signature provided
    function test_submitBlock() public {
        // sign block commitmenet with correct sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        // should emit BlockSubmitted event
        vm.expectEmit();
        emit BlockSubmitted(
            vm.addr(sequencerKey), header.rollupChainId, header.gasLimit, header.rewardAddress, header.blockDataHash
        );
        target.submitBlock(header, v, r, s, blockData);
    }

    // cannot submit block with invalid sequencer signer from non-permissioned key
    function test_notSequencer() public {
        // sign block commitmenet with NOT sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notSequencerKey, commit);

        vm.expectRevert(abi.encodeWithSelector(Zenith.BadSignature.selector, vm.addr(notSequencerKey)));
        target.submitBlock(header, v, r, s, blockData);
    }

    // cannot submit block with sequencer signature over different block header data
    function test_badSignature() public {
        // sign original block commitmenet with sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        // change header data from what was signed by sequencer
        header.rewardAddress = address(0);
        bytes32 newCommit = target.blockCommitment(header);
        address derivedSigner = ecrecover(newCommit, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(Zenith.BadSignature.selector, derivedSigner));
        target.submitBlock(header, v, r, s, blockData);
    }

    // cannot submit two rollup blocks within one host block
    function test_onePerBlock() public {
        // sign block commitmenet with correct sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        // should emit BlockSubmitted event
        vm.expectEmit();
        emit BlockSubmitted(
            vm.addr(sequencerKey), header.rollupChainId, header.gasLimit, header.rewardAddress, header.blockDataHash
        );
        target.submitBlock(header, v, r, s, blockData);

        // should revert with OneRollupBlockPerHostBlock
        // (NOTE: this test works without changing the Header because forge does not increment block.number when it mines a transaction)
        vm.expectRevert(Zenith.OneRollupBlockPerHostBlock.selector);
        target.submitBlock(header, v, r, s, blockData);
    }
}
