//! SVM-level integration test for the Zignocchio Escrow program under
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

const ESCROW_SEED: &[u8] = b"escrow";
const ESCROW_DISCRIMINATOR: u8 = 0xE5;

fn program_id() -> Pubkey {
    Pubkey::new_from_array([6u8; 32])
}

fn make_instruction_data(taker: &Pubkey, amount: u64) -> Vec<u8> {
    let mut data = vec![0u8];
    data.extend_from_slice(taker.as_ref());
    data.extend_from_slice(&amount.to_le_bytes());
    data
}

#[tokio::test]
async fn test_escrow_make_and_accept() {
    let pid = program_id();
    let maker = Keypair::new();
    let taker = Keypair::new();
    let (escrow_pda, _bump) = Pubkey::find_program_address(&[ESCROW_SEED, maker.pubkey().as_ref()], &pid);
    let amount: u64 = 100_000_000;

    let mut program_test = ProgramTest::default();
    program_test.add_program("escrow", pid, None);
    program_test.add_account(
        maker.pubkey(),
        Account {
            lamports: 1_000_000_000,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );
    program_test.add_account(
        taker.pubkey(),
        Account {
            lamports: 1_000_000,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );
    program_test.add_account(
        escrow_pda,
        Account {
            lamports: 0,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );

    let (banks_client, payer, recent_blockhash) = program_test.start().await;

    let make_ix = Instruction {
        program_id: pid,
        accounts: vec![
            AccountMeta::new(maker.pubkey(), true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new_readonly(system_program::id(), false),
        ],
        data: make_instruction_data(&taker.pubkey(), amount),
    };
    let mut make_tx = Transaction::new_with_payer(&[make_ix], Some(&payer.pubkey()));
    make_tx.sign(&[&payer, &maker], recent_blockhash);

    let make_result = banks_client.process_transaction(make_tx).await;
    assert!(make_result.is_ok(), "make should succeed: {:?}", make_result);

    let escrow_post = banks_client
        .get_account(escrow_pda)
        .await
        .expect("escrow fetch after make should succeed")
        .expect("escrow account should exist after make");
    assert_eq!(escrow_post.owner, pid);
    assert_eq!(escrow_post.data[0], ESCROW_DISCRIMINATOR);
    assert_eq!(&escrow_post.data[1..33], maker.pubkey().as_ref());
    assert_eq!(&escrow_post.data[33..65], taker.pubkey().as_ref());
    let stored_amount = u64::from_le_bytes(escrow_post.data[72..80].try_into().unwrap());
    assert_eq!(stored_amount, amount);

    let accept_ix = Instruction {
        program_id: pid,
        accounts: vec![
            AccountMeta::new(taker.pubkey(), true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new(maker.pubkey(), false),
        ],
        data: vec![1u8],
    };
    let blockhash = banks_client
        .get_latest_blockhash()
        .await
        .expect("latest blockhash should be available");
    let mut accept_tx = Transaction::new_with_payer(&[accept_ix], Some(&payer.pubkey()));
    accept_tx.sign(&[&payer, &taker], blockhash);

    let accept_result = banks_client.process_transaction(accept_tx).await;
    assert!(accept_result.is_ok(), "accept should succeed: {:?}", accept_result);

    let escrow_post2 = banks_client
        .get_account(escrow_pda)
        .await
        .expect("escrow fetch after accept should succeed");
    assert!(escrow_post2.is_none(), "escrow account should be closed after accept");

    let taker_post = banks_client
        .get_account(taker.pubkey())
        .await
        .expect("taker fetch should succeed")
        .expect("taker account should exist");
    assert!(taker_post.lamports > 1_000_000);
}
