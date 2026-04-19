//! SVM-level integration test for the Zignocchio LogOnly Lazy program under
//! solana-program-test.

use solana_program_test::ProgramTest;
use solana_sdk::{instruction::Instruction, pubkey::Pubkey, signature::Signer, transaction::Transaction};

fn program_id() -> Pubkey { Pubkey::new_from_array([19u8; 32]) }

#[tokio::test]
async fn test_logonly_lazy_executes_successfully() {
    let pid = program_id();
    let mut program_test = ProgramTest::default();
    program_test.add_program("logonly-lazy", pid, None);
    let (banks_client, payer, recent_blockhash) = program_test.start().await;
    let ix = Instruction { program_id: pid, accounts: vec![], data: vec![] };
    let mut tx = Transaction::new_with_payer(&[ix], Some(&payer.pubkey()));
    tx.sign(&[&payer], recent_blockhash);
    let result = banks_client.process_transaction(tx).await;
    assert!(result.is_ok(), "logonly-lazy should succeed: {:?}", result);
}
