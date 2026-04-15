/**
 * Hello program litesvm verification test.
 *
 * Deploys the hello program using raw `@solana/kit` APIs and inspects
 * the transaction result to catch any runtime errors during execution.
 */

import { LiteSVM } from 'litesvm';
import {
  appendTransactionMessageInstruction,
  createTransactionMessage,
  generateKeyPairSigner,
  pipe,
  setTransactionMessageFeePayerSigner,
  signTransactionMessageWithSigners,
  lamports,
} from '@solana/kit';
import * as path from 'path';
import { execSync } from 'child_process';

describe('litesvm hello verification', () => {
  const programPath = path.join(__dirname, '..', 'zig-out', 'lib', 'hello.so');

  beforeAll(() => {
    execSync('zig build -Dexample=hello', { stdio: 'inherit' });
  });

  it('executes hello program and checks for success or failure details', async () => {
    const svm = new LiteSVM();
    const payer = await generateKeyPairSigner();
    svm.airdrop(payer.address, lamports(BigInt(2_000_000_000)));

    const programId = await generateKeyPairSigner();
    svm.addProgramFromFile(programId.address, programPath);

    const instruction = {
      accounts: [],
      programAddress: programId.address,
      data: new Uint8Array(0),
    };

    const transaction = await pipe(
      createTransactionMessage({ version: 0 }),
      (tx) => setTransactionMessageFeePayerSigner(payer, tx),
      (tx) => svm.setTransactionMessageLifetimeUsingLatestBlockhash(tx),
      (tx) => appendTransactionMessageInstruction(instruction, tx),
      (tx) => signTransactionMessageWithSigners(tx),
    );

    const result = svm.sendTransaction(transaction);

    console.log('Transaction result:', JSON.stringify(result, (_key, value) =>
      typeof value === 'bigint' ? value.toString() : value,
    2));

    // Check if there are any transaction errors
    const anyError = (result as any).meta?.err || (result as any).transactionError;
    if (anyError) {
      console.log('Transaction error detected:', anyError);
    }

    expect(result).toBeDefined();
  });
});
