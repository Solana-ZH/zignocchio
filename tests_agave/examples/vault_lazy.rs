//! SVM-level integration test for the Zignocchio Vault Lazy program under
//! solana-program-test.

use solana_program_test::ProgramTest;
use solana_sdk::{account::Account, instruction::{AccountMeta, Instruction}, pubkey::Pubkey, signature::{Keypair, Signer}, system_program, transaction::Transaction};

fn program_id() -> Pubkey { Pubkey::new_from_array([15u8; 32]) }

#[tokio::test]
async fn test_vault_lazy_deposit_happy() {
    let pid = program_id();
    let user = Keypair::new();
    let (vault_pda, _bump) = Pubkey::find_program_address(&[b"vault", user.pubkey().as_ref()], &pid);
    let deposit_amount: u64 = 100_000_000;
    let mut program_test = ProgramTest::default();
    program_test.add_program("vault-lazy", pid, None);
    program_test.add_account(user.pubkey(), Account { lamports: 1_000_000_000, data: vec![], owner: system_program::id(), executable: false, rent_epoch: 0 });
    program_test.add_account(vault_pda, Account { lamports: 0, data: vec![], owner: system_program::id(), executable: false, rent_epoch: 0 });
    let (banks_client, payer, recent_blockhash) = program_test.start().await;
    let ix = Instruction { program_id: pid, accounts: vec![AccountMeta::new(user.pubkey(), true), AccountMeta::new(vault_pda, false), AccountMeta::new_readonly(system_program::id(), false)], data: { let mut data = vec![0u8]; data.extend_from_slice(&deposit_amount.to_le_bytes()); data } };
    let mut tx = Transaction::new_with_payer(&[ix], Some(&payer.pubkey()));
    tx.sign(&[&payer, &user], recent_blockhash);
    let result = banks_client.process_transaction(tx).await;
    assert!(result.is_ok(), "vault-lazy deposit should succeed: {:?}", result);
    let vault_post = banks_client.get_account(vault_pda).await.expect("vault fetch should succeed").expect("vault should exist after deposit");
    assert_eq!(vault_post.lamports, deposit_amount);
}
