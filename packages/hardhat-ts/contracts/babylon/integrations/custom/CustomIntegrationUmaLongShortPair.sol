// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBabController } from "../../interfaces/IBabController.sol";
import { CustomIntegration } from "./CustomIntegration.sol";
import { PreciseUnitMath } from "../../lib/PreciseUnitMath.sol";
import { LowGasSafeMath } from "../../lib/LowGasSafeMath.sol";
import { BytesLib } from "../../lib/BytesLib.sol";
import { ControllerLib } from "../../lib/ControllerLib.sol";

import {ILongShortPair} from  "../../../interface-uma/ILongShortPair.sol";

/**
 * @title CustomIntegrationSample
 * @author Babylon Finance Protocol
 *
 * Custom integration template
 */
contract CustomIntegrationUmaLongShortPair is CustomIntegration {
  using LowGasSafeMath for uint256;
  using PreciseUnitMath for uint256;
  using BytesLib for uint256;
  using ControllerLib for IBabController;

  /* ============ State Variables ============ */

  /* Add State variables here if any. Pass to the constructor */



  /* ============ Constructor ============ */

  /**
   * Creates the integration
   *
   * @param _controller                   Address of the controller
   */
  constructor(IBabController _controller) CustomIntegration("custom_uma_longshortpair_sample", _controller)  {
    require(address(_controller) != address(0), "invalid address");
  }

  /* =============== Internal Functions ============== */

  /**
   * Whether or not the data provided is valid
   *
   * hparam  _data                     Data provided
   * @return bool                      True if the data is correct
   */
  function _isValid(bytes memory _data) internal view override returns (bool) {
    // Check if the UMA token is not expired
    return _isUmaTokenNotExpired(_data);
  }

  function _isUmaTokenNotExpired(bytes memory _data) private view returns (bool) {
    ILongShortPair token = _getUmaTokenFromBytes(_data);
    return uint(token.contractState()) == 0;
  }

  function _isUmaTokenExpiredPriceReceived(bytes memory _data) private view returns (bool) {
    ILongShortPair token = _getUmaTokenFromBytes(_data);
    return uint(token.contractState()) == 2;
  }

  function _getUmaTokenFromBytes(bytes memory _data) private pure returns (ILongShortPair) {
    address umaToken = address(BytesLib.decodeOpDataAddressAssembly(_data, 12));
    ILongShortPair token = ILongShortPair(umaToken);
    return token;
  }

  /**
   * Which address needs to be approved (IERC-20) for the input tokens.
   *
   * hparam  _data                     Data provided
   * hparam  _opType                   O for enter, 1 for exit
   * @return address                   Address to approve the tokens to
   */
  function _getSpender(
    bytes calldata _data,
    uint8 /* _opType */
  ) internal pure override returns (address) {
    return address(BytesLib.decodeOpDataAddressAssembly(_data, 12));
  }

  /**
   * The address of the IERC-20 token obtained after entering this operation
   *
   * @param  _token                     Address provided as param
   * @return address                    Address of the resulting lp token
   */
  function _getResultToken(address _token) internal pure override returns (address) {
    // TODO find out how we can return long and short tokens here!
    ILongShortPair token = ILongShortPair(_token);
    return token.longToken.address;
  }

  /**
   * Return enter custom calldata
   *
   * hparam  _strategy                 Address of the strategy
   * hparam  _data                     OpData e.g. Address of the pool
   * hparam  _resultTokensOut          Amount of result tokens to send
   * hparam  _tokensIn                 Addresses of tokens to send to spender to enter
   * hparam  _maxAmountsIn             Amounts of tokens to send to spender
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getEnterCalldata(
    address, /* _strategy */
    bytes calldata _data,
    uint256, /* _resultTokensOut */
    address[] calldata _tokensIn,
    uint256[] calldata _maxAmountsIn
  )
    internal
    view
    override
    returns (
      address,
      uint256,
      bytes memory
    )
  {
    require(_isUmaTokenNotExpired(_data), "Cannot send tokens to expired UMA token!");
    address umaToken = address(BytesLib.decodeOpDataAddressAssembly(_data, 12));
    ILongShortPair token = ILongShortPair(umaToken);

    require(_tokensIn.length == 1 && _maxAmountsIn.length == 1, "Wrong amount of tokens provided");
    require(_tokensIn[0] == token.collateralToken.address, "Wrong token selected to send as collateral!");
    uint256 amountTokensToCreate = _maxAmountsIn[0] / token.collateralPerPair();
    bytes memory methodData = abi.encodeWithSelector(ILongShortPair.create.selector, amountTokensToCreate);

    return (umaToken, 0, methodData);
  }

  /**
   * Return exit custom calldata
   *
   * hparam  _strategy                 Address of the strategy
   * hparam  _data                     OpData e.g. Address of the pool
   * hparam  _resultTokensIn           Amount of result tokens to send
   * hparam  _tokensOut                Addresses of tokens to receive
   * hparam  _minAmountsOut            Amounts of input tokens to receive
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getExitCalldata(
    address, /* _strategy */
    bytes calldata _data,
    uint256 _resultTokensIn,
    address[] calldata, /* _tokensOut */
    uint256[] calldata /* _minAmountsOut */
  )
    internal
    view
    override
    returns (
      address,
      uint256,
      bytes memory
    )
  {
    require(_isUmaTokenExpiredPriceReceived(_data), "Cannot exit before the token is expired and price has been received!");
    ILongShortPair token = _getUmaTokenFromBytes(_data);
    bytes memory methodData = abi.encodeWithSelector(ILongShortPair.settle.selector, _resultTokensIn, _resultTokensIn);
    return (address(BytesLib.decodeOpDataAddressAssembly(_data, 12)), 0, methodData);
  }

  /**
   * The list of addresses of the IERC-20 tokens mined as rewards during the strategy
   *
   * hparam  _data                      Address provided as param
   * @return address[] memory           List of reward token addresses
   */
  function _getRewardTokens(
    address /* _data */
  ) internal pure override returns (address[] memory) {
    // No rewards
    return new address[](1);
  }

  /* ============ External Functions ============ */

  /**
   * The tokens to be purchased by the strategy on enter according to the weights.
   * Weights must add up to 1e18 (100%)
   *
   * hparam  _data                      Address provided as param
   * @return _inputTokens               List of input tokens to buy
   * @return _inputWeights              List of weights for the tokens to buy
   */
  function getInputTokensAndWeights(bytes calldata _data) external pure override returns (address[] memory _inputTokens, uint256[] memory _inputWeights) {
    address umaToken = address(BytesLib.decodeOpDataAddressAssembly(_data, 12));
    ILongShortPair token = ILongShortPair(umaToken);
    _inputTokens[0] = token.collateralToken.address;
    _inputWeights[0] = 1e18; // 100%
    return (_inputTokens, _inputWeights);
  }

  /**
   * The tokens to be received on exit.
   *
   * hparam  _data                      Bytes data
   * hparam  _liquidity                 Number with the amount of result tokens to exit
   * @return exitTokens                 List of output tokens to receive on exit
   * @return _minAmountsOut             List of min amounts for the output tokens to receive
   */
  function getOutputTokensAndMinAmountOut(
    bytes calldata _data,
    uint256 /* _liquidity */
  ) external pure override returns (address[] memory exitTokens, uint256[] memory _minAmountsOut) {
    address umaToken = address(BytesLib.decodeOpDataAddressAssembly(_data, 12));
    ILongShortPair token = ILongShortPair(umaToken);
    exitTokens[0] = token.collateralToken.address;
    _minAmountsOut[0] = 0;
    return (exitTokens, _minAmountsOut);
  }

  /**
   * The price of the result token based on the asset received on enter
   *
   * hparam  _data                      Bytes data
   * hparam  _tokenDenominator          Token we receive the capital in
   * @return uint256                    Amount of result tokens to receive
   */
  // function getPriceResultToken(
  //   bytes calldata _data,
  //   address _tokenDenominator
  // ) external pure override returns (uint256) {
  //   LongShortPair token = _getUmaTokenFromBytes(_data);
  //   require(_tokenDenominator == token.collateralToken, "Cannot give price in other denominator than in collateral token!");
  //   return token.collateralPerPair;
  // }

  function getPriceResultToken(
        bytes calldata, /* _data */
        address /* _tokenDenominator */
    ) external pure override returns (uint256) {
        /** FILL THIS */
        return 0;
    }
}