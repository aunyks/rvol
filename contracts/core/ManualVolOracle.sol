//SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.3;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract ManualVolOracle is AccessControl {
    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    mapping(address => uint256) public annualizedVols;

    /**
     * @notice Creates an volatility oracle for a pool
     * @param _admin is the admin
     */
    constructor(address _admin) {
        require(_admin != address(0), "!_admin");

        // Add _admin as admin
        _setupRole(ADMIN_ROLE, _admin);
    }

    /// @dev A modifier which checks that the caller has the admin role.
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "!admin");
        _;
    }

    /**
     * @notice Returns the standard deviation of the base currency in 10**8 i.e. 1*10**8 = 100%
     * @return standardDeviation is the standard deviation of the asset
     */
    function vol(address pool) public view returns (uint256 standardDeviation) {
        return 0;
    }

    /**
     * @notice Returns the annualized standard deviation of the base currency in 10**8 i.e. 1*10**8 = 100%
     * @return annualStdev is the annualized standard deviation of the asset
     */
    function annualizedVol(address pool)
        public
        view
        returns (uint256 annualStdev)
    {
        return annualizedVols[pool];
    }

    /**
     * @notice Sets the annualized standard deviation of the base currency of the `pool`
     * @param pool is the uniswap pool we want to set annualized volatility for
     * @param annualizedVol is the annualized volatility with 10**8 decimals i.e. 1*10**8 = 100%
     */
    function setAnnualizedVol(address pool, uint256 annualizedVol)
        external
        onlyAdmin
    {
        require(annualizedVol > 0, "!annualizedVol");
        annualizedVols[pool] = annualizedVol;
    }
}
