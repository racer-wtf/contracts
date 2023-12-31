pragma solidity ^0.8.0;

// SPDX-License-Identifier: Unlicensed

library Bytes4Set {
    struct Set {
        mapping(bytes4 => uint) keyPointers;
        bytes4[] keyList;
    }

    /**
     * @notice insert a key.
     * @dev duplicate keys are not permitted.
     * @param self storage pointer to a Set.
     * @param key value to insert.
     */
    function insert(Set storage self, bytes4 key) internal {
        require(
            !exists(self, key),
            "Bytes32Set: key already exists in the set."
        );
        self.keyPointers[key] = self.keyList.length;
        self.keyList.push(key);
    }

    /**
     * @notice remove a key.
     * @dev key to remove must exist.
     * @param self storage pointer to a Set.
     * @param key value to remove.
     */
    function remove(Set storage self, bytes4 key) internal {
        require(
            exists(self, key),
            "Bytes32Set: key does not exist in the set."
        );
        uint last = count(self) - 1;
        uint rowToReplace = self.keyPointers[key];
        if (rowToReplace != last) {
            bytes4 keyToMove = self.keyList[last];
            self.keyPointers[keyToMove] = rowToReplace;
            self.keyList[rowToReplace] = keyToMove;
        }
        delete self.keyPointers[key];
        self.keyList.pop();
    }

    /**
     * @notice count the keys.
     * @param self storage pointer to a Set.
     */
    function count(Set storage self) internal view returns (uint) {
        return (self.keyList.length);
    }

    /**
     * @notice check if a key is in the Set.
     * @param self storage pointer to a Set.
     * @param key value to check.
     * @return bool true: Set member, false: not a Set member.
     */
    function exists(Set storage self, bytes4 key) internal view returns (bool) {
        if (self.keyList.length == 0) return false;
        return self.keyList[self.keyPointers[key]] == key;
    }

    /**
     * @notice fetch a key by row (enumerate).
     * @param self storage pointer to a Set.
     * @param index row to enumerate. Must be < count() - 1.
     */
    function get(
        Set storage self,
        uint index
    ) internal view returns (bytes4) {
        return self.keyList[index];
    }
}
