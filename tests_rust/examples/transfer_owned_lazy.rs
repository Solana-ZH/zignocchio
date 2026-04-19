//! SVM-level integration test for the experimental Transfer Owned Lazy benchmark.

use mollusk_svm::Mollusk;
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [11u8; 32];

fn program_id() -> Pubkey {
    Pubkey::new_from_array(PROGRAM_ID_BYTES)
}

fn setup_mollusk() -> Mollusk {
    let elf_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("zig-out")
        .join("lib")
        .join("transfer-owned-lazy.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| {
        panic!(
            "failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=transfer-owned-lazy` first.",
            elf_path.display(),
            error
        )
    });
    let pid = program_id();
    let loader_v3 = solana_pubkey::pubkey!("BPFLoaderUpgradeab1e11111111111111111111111");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(&pid, &loader_v3, &elf);
    mollusk
}

#[test]
fn test_transfer_owned_lazy_happy() {
    let mollusk = setup_mollusk();
    let source = Pubkey::new_unique();
    let destination = Pubkey::new_unique();
    let source_lamports: u64 = 555_555;
    let destination_lamports: u64 = 890_875;

    let ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(source, false),
            AccountMeta::new(destination, false),
        ],
        data: source_lamports.to_le_bytes().to_vec(),
    };

    let source_acc = Account {
        lamports: source_lamports,
        data: vec![0],
        owner: program_id(),
        executable: false,
        rent_epoch: 0,
    };
    let destination_acc = Account {
        lamports: destination_lamports,
        ..Account::default()
    };

    let result = mollusk.process_instruction(&ix, &[(source, source_acc), (destination, destination_acc)]);
    assert!(
        !result.program_result.is_err(),
        "transfer-owned-lazy should succeed: {:?}",
        result.program_result
    );
}
