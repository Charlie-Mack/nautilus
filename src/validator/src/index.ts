import { Field, Mina, PrivateKey, AccountUpdate } from 'o1js';

const main = async () => {
  const randomField = Field.random();
  console.log('Random field: ', randomField.toString());
};

main();
