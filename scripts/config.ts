export enum Network {
  LOCAL = 1337,
  MAINNET = 1,
  GNOSIS = 100,
  KOVAN = 42,
  GOERLI = 5,
  MUMBAI = 80001,
  BNB = 97
}

export type NetworkConfig = {
  proofOfHumanityAddress: string;
};

const kovan: NetworkConfig = {
  proofOfHumanityAddress: "",
};

const local = {} as NetworkConfig;
const mainnet = {} as NetworkConfig;
const gnosis = {} as NetworkConfig;
const goerli = {} as NetworkConfig;
const mumbai = {} as NetworkConfig;
const bnb = {} as NetworkConfig;

export const configs: { [networkId in Network]: NetworkConfig } = {
  [Network.LOCAL]: local,
  [Network.MAINNET]: mainnet,
  [Network.GNOSIS]: gnosis,
  [Network.KOVAN]: kovan,
  [Network.GOERLI]: goerli,
  [Network.MUMBAI]: mumbai,
  [Network.BNB]: bnb,
};

export const getConfig = (networkId: Network): NetworkConfig => {
  return configs[networkId];
};
