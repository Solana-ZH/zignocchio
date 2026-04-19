//! SVM-level integration test for the Zignocchio PDA Storage program under
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

const STORAGE_SEED: &[u8] = b"storage";

fn program_id() -> Pubkey {
    Pubkey::new_from_array([5u8; 32])
}

#[tokio::test]
async fn test_pda_storage_init_and_update() {
    let pid = program_id();
    let user = Keypair::new();
    let (storage_pda, _bump) = Pubkey::find_program_address(&[STORAGE_SEED, user.pubkey().as_ref()], &pid);

    let mut program_test = ProgramTest::default();
    program_test.add_program("pda-storage", pid, None);
    program_test.add_account(
        storage_pda,
        Account {
            lamports: 0,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );
    program_test.add_account(
        user.pubkey(),
        Account {
            lamports: 1_000_000,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );

    let (banks_client, payer, recent_blockhash) = program_test.start().await;

    let initial_value: u64 = 42;
    let init_ix = Instruction {
        program_id: pid,
        accounts: vec![
            AccountMeta::new(payer.pubkey(), true),
            AccountMeta::new(storage_pda, false),
            AccountMeta::new(user.pubkey(), true),
            AccountMeta::new_readonly(system_program::id(), false),
        ],
        data: {
            let mut data = vec![0u8];
            data.extend_from_slice(&initial_value.to_le_bytes());
            data
        },
    };

    let mut init_tx = Transaction::new_with_payer(&[init_ix], Some(&payer.pubkey()));
    init_tx.sign(&[&payer, &user], recent_blockhash);

    let init_result = banks_client.process_transaction(init_tx).await;
    assert!(init_result.is_ok(), "init should succeed: {:?}", init_result);

    let storage_post = banks_client
        .get_account(storage_pda)
        .await
        .expect("storage fetch after init should succeed")
        .expect("storage PDA should exist after init");
    assert_eq!(&storage_post.data[0..32], user.pubkey().as_ref());
    let stored_value = u64::from_le_bytes(storage_post.data[32..40].try_into().unwrap());
    assert_eq!(stored_value, initial_value);

    let new_value: u64 = 100;
    let update_ix = Instruction {
        program_id: pid,
        accounts: vec![
            AccountMeta::new(storage_pda, false),
            AccountMeta::new(user.pubkey(), true),
        ],
        data: {
            let mut data = vec![1u8];
            data.extend_from_slice(&new_value.to_le_bytes());
            data
        },
    };

    let blockhash = banks_client
        .get_latest_blockhash()
        .await
        .expect("latest blockhash should be available");
    let mut update_tx = Transaction::new_with_payer(&[update_ix], Some(&payer.pubkey()));
    update_tx.sign(&[&payer, &user], blockhash);

    let update_result = banks_client.process_transaction(update_tx).await;
    assert!(update_result.is_ok(), "update should succeed: {:?}", update_result);

    let storage_post2 = banks_client
        .get_account(storage_pda)
        .await
        .expect("storage fetch after update should succeed")
        .expect("storage PDA should still exist after update");
    let stored_value2 = u64::from_le_bytes(storage_post2.data[32..40].try_into().unwrap());
    assert_eq!(stored_value2, new_value);
}
