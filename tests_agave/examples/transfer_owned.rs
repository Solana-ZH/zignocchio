//! SVM-level integration test for the Zignocchio Transfer Owned benchmark under
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
    Pubkey::new_from_array([10u8; 32])
}

#[tokio::test]
async fn test_transfer_owned_happy() {
    let pid = program_id();
    let source = Pubkey::new_unique();
    let destination = Pubkey::new_unique();
    let source_lamports: u64 = 555_555;
    let destination_lamports: u64 = 890_875;

    let mut program_test = ProgramTest::default();
    program_test.add_program("transfer-owned", pid, None);
    program_test.add_account(
        source,
        Account {
            lamports: source_lamports,
            data: vec![0],
            owner: pid,
            executable: false,
            rent_epoch: 0,
        },
    );
    program_test.add_account(
        destination,
        Account {
            lamports: destination_lamports,
            ..Account::default()
        },
    );

    let (banks_client, payer, recent_blockhash) = program_test.start().await;

    let ix = Instruction {
        program_id: pid,
        accounts: vec![
            AccountMeta::new(source, false),
            AccountMeta::new(destination, false),
        ],
        data: source_lamports.to_le_bytes().to_vec(),
    };
    let mut tx = Transaction::new_with_payer(&[ix], Some(&payer.pubkey()));
    tx.sign(&[&payer], recent_blockhash);

    let result = banks_client.process_transaction(tx).await;
    assert!(result.is_ok(), "transfer-owned should succeed: {:?}", result);

    let source_post = banks_client
        .get_account(source)
        .await
        .expect("source fetch should succeed");
    assert_eq!(source_post, None, "source should be drained and removed");

    let destination_post = banks_client
        .get_account(destination)
        .await
        .expect("destination fetch should succeed")
        .expect("destination account should exist");
    assert_eq!(destination_post.lamports, destination_lamports + source_lamports);
}
