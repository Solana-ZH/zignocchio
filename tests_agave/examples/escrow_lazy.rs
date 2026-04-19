//! SVM-level integration test for the Zignocchio Escrow Lazy program under
//! solana-program-test.

use solana_program_test::ProgramTest;
use solana_sdk::{account::Account, instruction::{AccountMeta, Instruction}, pubkey::Pubkey, signature::{Keypair, Signer}, system_program, transaction::Transaction};

const ESCROW_SEED: &[u8] = b"escrow";

fn program_id() -> Pubkey { Pubkey::new_from_array([17u8; 32]) }

#[tokio::test]
async fn test_escrow_lazy_make_and_accept() {
    let pid = program_id();
    let maker = Keypair::new();
    let taker = Keypair::new();
    let (escrow_pda, _bump) = Pubkey::find_program_address(&[ESCROW_SEED, maker.pubkey().as_ref()], &pid);
    let amount: u64 = 100_000_000;
    let mut program_test = ProgramTest::default();
    program_test.add_program("escrow-lazy", pid, None);
    program_test.add_account(maker.pubkey(), Account { lamports: 1_000_000_000, data: vec![], owner: system_program::id(), executable: false, rent_epoch: 0 });
    program_test.add_account(taker.pubkey(), Account { lamports: 1_000_000, data: vec![], owner: system_program::id(), executable: false, rent_epoch: 0 });
    program_test.add_account(escrow_pda, Account { lamports: 0, data: vec![], owner: system_program::id(), executable: false, rent_epoch: 0 });
    let (banks_client, payer, recent_blockhash) = program_test.start().await;
    let make_ix = Instruction { program_id: pid, accounts: vec![AccountMeta::new(maker.pubkey(), true), AccountMeta::new(escrow_pda, false), AccountMeta::new_readonly(system_program::id(), false)], data: { let mut data = vec![0u8]; data.extend_from_slice(taker.pubkey().as_ref()); data.extend_from_slice(&amount.to_le_bytes()); data } };
    let mut make_tx = Transaction::new_with_payer(&[make_ix], Some(&payer.pubkey()));
    make_tx.sign(&[&payer, &maker], recent_blockhash);
    let make_result = banks_client.process_transaction(make_tx).await;
    assert!(make_result.is_ok(), "make should succeed: {:?}", make_result);
    let accept_ix = Instruction { program_id: pid, accounts: vec![AccountMeta::new(taker.pubkey(), true), AccountMeta::new(escrow_pda, false), AccountMeta::new(maker.pubkey(), false)], data: vec![1u8] };
    let blockhash = banks_client.get_latest_blockhash().await.expect("latest blockhash should be available");
    let mut accept_tx = Transaction::new_with_payer(&[accept_ix], Some(&payer.pubkey()));
    accept_tx.sign(&[&payer, &taker], blockhash);
    let accept_result = banks_client.process_transaction(accept_tx).await;
    assert!(accept_result.is_ok(), "accept should succeed: {:?}", accept_result);
}
