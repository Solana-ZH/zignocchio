//! SVM-level integration test for the Zignocchio PDA Storage Lazy program.

use mollusk_svm::{program::keyed_account_for_system_program, Mollusk};
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [16u8; 32];
const SYSTEM_PROGRAM_ID: Pubkey = solana_pubkey::pubkey!("11111111111111111111111111111111");
const STORAGE_SEED: &[u8] = b"storage";

fn program_id() -> Pubkey { Pubkey::new_from_array(PROGRAM_ID_BYTES) }

fn setup_mollusk() -> Mollusk {
    let elf_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join("zig-out").join("lib").join("pda-storage-lazy.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| panic!("failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=pda-storage-lazy` first.", elf_path.display(), error));
    let pid = program_id();
    let loader_v3 = solana_pubkey::pubkey!("BPFLoaderUpgradeab1e11111111111111111111111");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(&pid, &loader_v3, &elf);
    mollusk.program_cache.add_builtin(mollusk_svm::program::Builtin { program_id: SYSTEM_PROGRAM_ID, name: "system_program", entrypoint: solana_system_program::system_processor::Entrypoint::vm });
    mollusk
}

#[test]
fn test_pda_storage_lazy_init_and_update() {
    let mollusk = setup_mollusk();
    let payer = Pubkey::new_unique();
    let user = Pubkey::new_unique();
    let (storage_pda, _bump) = Pubkey::find_program_address(&[STORAGE_SEED, user.as_ref()], &program_id());
    let init_ix = Instruction { program_id: program_id(), accounts: vec![AccountMeta::new(payer, true), AccountMeta::new(storage_pda, false), AccountMeta::new(user, true), AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false)], data: { let mut data = vec![0u8]; data.extend_from_slice(&42u64.to_le_bytes()); data } };
    let payer_acc = Account { lamports: 2_000_000_000, ..Account::default() };
    let storage_acc = Account { lamports: 0, data: vec![], owner: SYSTEM_PROGRAM_ID, executable: false, rent_epoch: 0 };
    let user_acc = Account { lamports: 1_000_000, ..Account::default() };
    let result = mollusk.process_instruction(&init_ix, &[(payer, payer_acc), (storage_pda, storage_acc), (user, user_acc), keyed_account_for_system_program()]);
    assert!(!result.program_result.is_err(), "pda-storage-lazy init should succeed: {:?}", result.program_result);
    let update_ix = Instruction { program_id: program_id(), accounts: vec![AccountMeta::new(storage_pda, false), AccountMeta::new(user, true)], data: { let mut data = vec![1u8]; data.extend_from_slice(&100u64.to_le_bytes()); data } };
    let result2 = mollusk.process_instruction(&update_ix, &[(storage_pda, result.resulting_accounts[1].1.clone()), (user, result.resulting_accounts[2].1.clone())]);
    assert!(!result2.program_result.is_err(), "pda-storage-lazy update should succeed: {:?}", result2.program_result);
    let stored_value = u64::from_le_bytes(result2.resulting_accounts[0].1.data[32..40].try_into().unwrap());
    assert_eq!(stored_value, 100);
}
