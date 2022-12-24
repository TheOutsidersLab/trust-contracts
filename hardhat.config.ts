import {HardhatUserConfig} from "hardhat/config";
import {NetworkUserConfig} from "hardhat/types";
import {config as dotenvConfig} from "dotenv";
import {resolve} from "path";
import {Network} from "./scripts/config";
import "./scripts/deploy";
import "./scripts/iexecTestDeploy";
import "@nomicfoundation/hardhat-toolbox";

dotenvConfig({path: resolve(__dirname, "./.env")});

const mnemonic: string | undefined = process.env.MNEMONIC;
if (!mnemonic) {
  throw new Error("Please set your MNEMONIC in a .env file");
}

const infuraApiKey: string | undefined = process.env.INFURA_API_KEY;
const nodeRealApiKeyGoerli: string | undefined = process.env.NODE_REAL_API_KEY_GOERLI;
const nodeRealApiKeyBnb: string | undefined = process.env.NODE_REAL_API_KEY_BNB;
if (!infuraApiKey && !nodeRealApiKeyGoerli && !nodeRealApiKeyBnb) {
  throw new Error("Please set an INFURA_API_KEY or NODE_REAL_API_KEY_GOERLI or NODE_REAL_API_KEY_BNB in a .env file");
}

function getChainConfig(chain: Network): NetworkUserConfig {
  let jsonRpcUrl: string;
  switch (chain) {
    case Network.GOERLI:
      jsonRpcUrl = "https://eth-goerli.nodereal.io/v1/" + nodeRealApiKeyGoerli;
      break;
    case Network.BNB:
      jsonRpcUrl = "https://bsc-testnet.nodereal.io/v1/" + nodeRealApiKeyBnb;
      break;
    case Network.MUMBAI:
      jsonRpcUrl = "https://polygon-mumbai.infura.io/v3/" + infuraApiKey;
      break;
    default:
      jsonRpcUrl = "https://goerli.infura.io/v3/" + infuraApiKey;
  }

  return {
    accounts: {
      count: 10, mnemonic, path: "m/44'/60'/0'/0",
    }, chainId: chain, url: jsonRpcUrl,
  };
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      xdai: process.env.GNOSIS_API_KEY || "",
      goerli: process.env.ETHERSCAN_API_KEY || "",
      kovan: process.env.ETHERSCAN_API_KEY || "",
      polygonMumbai: process.env.POLYGONSCAN_API_KEY || "",
    },
  },
  gasReporter: {
    currency: "USD",
    enabled: !!process.env.REPORT_GAS,
    excludeContracts: [],
    src: "./contracts",
  },
  networks: {
    hardhat: {
      accounts: {
        mnemonic,
      },
      chainId: Network.LOCAL,
    },
    mainnet: getChainConfig(Network.MAINNET),
    goerli: getChainConfig(Network.GOERLI),
    gnosis: getChainConfig(Network.GNOSIS),
    kovan: getChainConfig(Network.KOVAN),
    mumbai: getChainConfig(Network.MUMBAI),
    bnbTestnet: getChainConfig(Network.BNB),
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
};

export default config;
