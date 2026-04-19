//! SVM-level integration test for the Zignocchio Escrow Lazy program.

use mollusk_svm::{program::keyed_account_for_system_program, Mollusk};
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [17u8; 32];
const SYSTEM_PROGRAM_ID: Pubkey = solana_pubkey::pubkey!("11111111111111111111111111111111");
const ESCROW_SEED: &[u8] = b"escrow";

fn program_id() -> Pubkey { Pubkey::new_from_array(PROGRAM_ID_BYTES) }

fn setup_mollusk() -> Mollusk {
    let elf_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join("zig-out").join("lib").join("escrow-lazy.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| panic!("failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=escrow-lazy` first.", elf_path.display(), error));
    let pid = program_id();
    let loader_v3 = solana_pubkey::pubkey!("BPFLoaderUpgradeab1e11111111111111111111111");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(&pid, &loader_v3, &elf);
    mollusk.program_cache.add_builtin(mollusk_svm::program::Builtin { program_id: SYSTEM_PROGRAM_ID, name: "system_program", entrypoint: solana_system_program::system_processor::Entrypoint::vm });
    mollusk
}

#[test]
fn test_escrow_lazy_make_and_accept() {
    let mollusk = setup_mollusk();
    let maker = Pubkey::new_unique();
    let taker = Pubkey::new_unique();
    let (escrow_pda, _bump) = Pubkey::find_program_address(&[ESCROW_SEED, maker.as_ref()], &program_id());
    let amount: u64 = 100_000_000;
    let make_ix = Instruction { program_id: program_id(), accounts: vec![AccountMeta::new(maker, true), AccountMeta::new(escrow_pda, false), AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false)], data: { let mut data = vec![0u8]; data.extend_from_slice(taker.as_ref()); data.extend_from_slice(&amount.to_le_bytes()); data } };
    let maker_acc = Account { lamports: 1_000_000_000, ..Account::default() };
    let escrow_acc = Account { lamports: 0, data: vec![], owner: SYSTEM_PROGRAM_ID, executable: false, rent_epoch: 0 };
    let result = mollusk.process_instruction(&make_ix, &[(maker, maker_acc), (escrow_pda, escrow_acc), keyed_account_for_system_program()]);
    assert!(!result.program_result.is_err(), "escrow-lazy make should succeed: {:?}", result.program_result);
    let accept_ix = Instruction { program_id: program_id(), accounts: vec![AccountMeta::new(taker, true), AccountMeta::new(escrow_pda, false), AccountMeta::new(maker, false)], data: vec![1u8] };
    let taker_acc = Account { lamports: 1_000_000, ..Account::default() };
    let result2 = mollusk.process_instruction(&accept_ix, &[(taker, taker_acc), (escrow_pda, result.resulting_accounts[1].1.clone()), (maker, result.resulting_accounts[0].1.clone())]);
    assert!(!result2.program_result.is_err(), "escrow-lazy accept should succeed: {:?}", result2.program_result);
    assert_eq!(result2.resulting_accounts[1].1.lamports, 0);
}
