//! SVM-level integration test for the Zignocchio Transfer SOL program under
//! solana-program-test.

use solana_program_test::ProgramTest;
use solana_sdk::{
    account::Account,
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    system_program,
    transaction::Transaction,
};

fn program_id() -> Pubkey {
    Pubkey::new_from_array([4u8; 32])
}

#[tokio::test]
async fn test_transfer_sol_happy() {
    let pid = program_id();
    let from = Keypair::new();
    let to = Pubkey::new_unique();
    let amount: u64 = 100_000_000;

    let mut program_test = ProgramTest::default();
    program_test.add_program("transfer-sol", pid, None);
    program_test.add_account(
        from.pubkey(),
        Account {
            lamports: 1_000_000_000,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );
    program_test.add_account(
        to,
        Account {
            lamports: 0,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );

    let (banks_client, payer, recent_blockhash) = program_test.start().await;

    let ix = Instruction {
        program_id: pid,
        accounts: vec![
            AccountMeta::new(from.pubkey(), true),
            AccountMeta::new(to, false),
            AccountMeta::new_readonly(system_program::id(), false),
        ],
        data: amount.to_le_bytes().to_vec(),
    };
    let mut tx = Transaction::new_with_payer(&[ix], Some(&payer.pubkey()));
    tx.sign(&[&payer, &from], recent_blockhash);

    let result = banks_client.process_transaction(tx).await;
    assert!(result.is_ok(), "transfer should succeed: {:?}", result);

    let from_post = banks_client
        .get_account(from.pubkey())
        .await
        .expect("source fetch should succeed")
        .expect("source account should exist");
    let to_post = banks_client
        .get_account(to)
        .await
        .expect("destination fetch should succeed")
        .expect("destination account should exist");

    assert_eq!(from_post.lamports, 900_000_000);
    assert_eq!(to_post.lamports, amount);
}
