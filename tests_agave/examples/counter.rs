//! SVM-level integration test for the Zignocchio Counter program under
//! solana-program-test.

use solana_program_test::ProgramTest;
use solana_sdk::{
    account::Account,
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::Signer,
    transaction::Transaction,
};

fn program_id() -> Pubkey {
    Pubkey::new_from_array([2u8; 32])
}

#[tokio::test]
async fn test_counter_increment() {
    let pid = program_id();
    let counter = Pubkey::new_unique();

    let mut program_test = ProgramTest::default();
    program_test.add_program("counter", pid, None);
    program_test.add_account(
        counter,
        Account {
            lamports: 1_000_000,
            data: vec![0u8; 8],
            owner: pid,
            executable: false,
            rent_epoch: 0,
        },
    );

    let (banks_client, payer, recent_blockhash) = program_test.start().await;

    let ix = Instruction {
        program_id: pid,
        accounts: vec![AccountMeta::new(counter, false)],
        data: vec![0],
    };
    let mut tx = Transaction::new_with_payer(&[ix], Some(&payer.pubkey()));
    tx.sign(&[&payer], recent_blockhash);

    let result = banks_client.process_transaction(tx).await;
    assert!(result.is_ok(), "counter increment should succeed: {:?}", result);

    let counter_post = banks_client
        .get_account(counter)
        .await
        .expect("counter fetch should succeed")
        .expect("counter account should exist");
    let value = u64::from_le_bytes(counter_post.data[0..8].try_into().unwrap());
    assert_eq!(value, 1, "counter should be incremented to 1");
}
