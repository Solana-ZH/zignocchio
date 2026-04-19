use mollusk_svm::{program::keyed_account_for_system_program, Mollusk};
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;
use std::{error::Error, path::Path};

fn boxed_error(message: impl Into<String>) -> Box<dyn Error> {
    Box::new(std::io::Error::other(message.into()))
}

const HELLO_PROGRAM_ID_BYTES: [u8; 32] = [1u8; 32];
const COUNTER_PROGRAM_ID_BYTES: [u8; 32] = [2u8; 32];
const VAULT_PROGRAM_ID_BYTES: [u8; 32] = [3u8; 32];
const TRANSFER_SOL_PROGRAM_ID_BYTES: [u8; 32] = [4u8; 32];
const PDA_STORAGE_PROGRAM_ID_BYTES: [u8; 32] = [5u8; 32];
const ESCROW_PROGRAM_ID_BYTES: [u8; 32] = [6u8; 32];
const NOOP_PROGRAM_ID_BYTES: [u8; 32] = [8u8; 32];
const LOGONLY_PROGRAM_ID_BYTES: [u8; 32] = [9u8; 32];
const TRANSFER_OWNED_PROGRAM_ID_BYTES: [u8; 32] = [10u8; 32];
const TRANSFER_OWNED_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [11u8; 32];
const HELLO_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [12u8; 32];
const TRANSFER_SOL_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [13u8; 32];
const COUNTER_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [14u8; 32];
const VAULT_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [15u8; 32];
const PDA_STORAGE_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [16u8; 32];
const ESCROW_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [17u8; 32];
const NOOP_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [18u8; 32];
const LOGONLY_LAZY_PROGRAM_ID_BYTES: [u8; 32] = [19u8; 32];

const SYSTEM_PROGRAM_ID: Pubkey = solana_pubkey::pubkey!("11111111111111111111111111111111");
const STORAGE_SEED: &[u8] = b"storage";
const ESCROW_SEED: &[u8] = b"escrow";

fn usage() -> &'static str {
    "usage: cargo run --manifest-path tests_rust/Cargo.toml --bin cu_probe -- --example <name> --artifact <path/to/program.so>"
}

fn program_id_for(example: &str) -> Result<Pubkey, Box<dyn Error>> {
    match example {
        "hello" => Ok(Pubkey::new_from_array(HELLO_PROGRAM_ID_BYTES)),
        "counter" => Ok(Pubkey::new_from_array(COUNTER_PROGRAM_ID_BYTES)),
        "vault" => Ok(Pubkey::new_from_array(VAULT_PROGRAM_ID_BYTES)),
        "transfer-sol" => Ok(Pubkey::new_from_array(TRANSFER_SOL_PROGRAM_ID_BYTES)),
        "pda-storage" => Ok(Pubkey::new_from_array(PDA_STORAGE_PROGRAM_ID_BYTES)),
        "escrow" => Ok(Pubkey::new_from_array(ESCROW_PROGRAM_ID_BYTES)),
        "noop" => Ok(Pubkey::new_from_array(NOOP_PROGRAM_ID_BYTES)),
        "logonly" => Ok(Pubkey::new_from_array(LOGONLY_PROGRAM_ID_BYTES)),
        "transfer-owned" => Ok(Pubkey::new_from_array(TRANSFER_OWNED_PROGRAM_ID_BYTES)),
        "transfer-owned-lazy" => Ok(Pubkey::new_from_array(TRANSFER_OWNED_LAZY_PROGRAM_ID_BYTES)),
        "hello-lazy" => Ok(Pubkey::new_from_array(HELLO_LAZY_PROGRAM_ID_BYTES)),
        "transfer-sol-lazy" => Ok(Pubkey::new_from_array(TRANSFER_SOL_LAZY_PROGRAM_ID_BYTES)),
        "counter-lazy" => Ok(Pubkey::new_from_array(COUNTER_LAZY_PROGRAM_ID_BYTES)),
        "vault-lazy" => Ok(Pubkey::new_from_array(VAULT_LAZY_PROGRAM_ID_BYTES)),
        "pda-storage-lazy" => Ok(Pubkey::new_from_array(PDA_STORAGE_LAZY_PROGRAM_ID_BYTES)),
        "escrow-lazy" => Ok(Pubkey::new_from_array(ESCROW_LAZY_PROGRAM_ID_BYTES)),
        "noop-lazy" => Ok(Pubkey::new_from_array(NOOP_LAZY_PROGRAM_ID_BYTES)),
        "logonly-lazy" => Ok(Pubkey::new_from_array(LOGONLY_LAZY_PROGRAM_ID_BYTES)),
        _ => Err(boxed_error(format!("unsupported example for CU probing: {example}"))),
    }
}

fn load_mollusk(program_id: &Pubkey, artifact: &Path, add_system_program: bool) -> Result<Mollusk, Box<dyn Error>> {
    let elf = std::fs::read(artifact)?;
    let loader_v3 = solana_pubkey::pubkey!("BPFLoaderUpgradeab1e11111111111111111111111");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(program_id, &loader_v3, &elf);
    if add_system_program {
        mollusk.program_cache.add_builtin(mollusk_svm::program::Builtin {
            program_id: SYSTEM_PROGRAM_ID,
            name: "system_program",
            entrypoint: solana_system_program::system_processor::Entrypoint::vm,
        });
    }
    Ok(mollusk)
}

fn print_cu(scenario: &str, cu: u64) {
    println!("CU\t{scenario}\t{cu}");
}

fn probe_hello(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("hello")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let ix = Instruction {
        program_id,
        accounts: vec![],
        data: vec![],
    };
    let result = mollusk.process_instruction(&ix, &[]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("hello execution failed: {:?}", result.program_result)));
    }
    print_cu("hello", result.compute_units_consumed);
    Ok(())
}

fn probe_hello_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("hello-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let ix = Instruction {
        program_id,
        accounts: vec![],
        data: vec![],
    };
    let result = mollusk.process_instruction(&ix, &[]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("hello-lazy execution failed: {:?}", result.program_result)));
    }
    print_cu("hello-lazy", result.compute_units_consumed);
    Ok(())
}

fn probe_noop(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("noop")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let ix = Instruction { program_id, accounts: vec![], data: vec![] };
    let result = mollusk.process_instruction(&ix, &[]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("noop execution failed: {:?}", result.program_result)));
    }
    print_cu("noop", result.compute_units_consumed);
    Ok(())
}

fn probe_noop_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("noop-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let ix = Instruction { program_id, accounts: vec![], data: vec![] };
    let result = mollusk.process_instruction(&ix, &[]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("noop-lazy execution failed: {:?}", result.program_result)));
    }
    print_cu("noop-lazy", result.compute_units_consumed);
    Ok(())
}

fn probe_logonly(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("logonly")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let ix = Instruction { program_id, accounts: vec![], data: vec![] };
    let result = mollusk.process_instruction(&ix, &[]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("logonly execution failed: {:?}", result.program_result)));
    }
    print_cu("logonly", result.compute_units_consumed);
    Ok(())
}

fn probe_logonly_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("logonly-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let ix = Instruction { program_id, accounts: vec![], data: vec![] };
    let result = mollusk.process_instruction(&ix, &[]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("logonly-lazy execution failed: {:?}", result.program_result)));
    }
    print_cu("logonly-lazy", result.compute_units_consumed);
    Ok(())
}

fn probe_counter(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("counter")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let counter = Pubkey::new_unique();
    let ix = Instruction {
        program_id,
        accounts: vec![AccountMeta::new(counter, false)],
        data: vec![0],
    };
    let counter_acc = Account {
        lamports: 1_000_000,
        data: vec![0u8; 8],
        owner: program_id,
        executable: false,
        rent_epoch: 0,
    };
    let result = mollusk.process_instruction(&ix, &[(counter, counter_acc)]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("counter execution failed: {:?}", result.program_result)));
    }
    print_cu("increment", result.compute_units_consumed);
    Ok(())
}

fn probe_counter_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("counter-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let counter = Pubkey::new_unique();
    let ix = Instruction {
        program_id,
        accounts: vec![AccountMeta::new(counter, false)],
        data: vec![0],
    };
    let counter_acc = Account {
        lamports: 1_000_000,
        data: vec![0u8; 8],
        owner: program_id,
        executable: false,
        rent_epoch: 0,
    };
    let result = mollusk.process_instruction(&ix, &[(counter, counter_acc)]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("counter-lazy execution failed: {:?}", result.program_result)));
    }
    print_cu("counter-lazy", result.compute_units_consumed);
    Ok(())
}

fn probe_vault(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("vault")?;
    let mollusk = load_mollusk(&program_id, artifact, true)?;
    let user = Pubkey::new_unique();
    let (vault_pda, _bump) = Pubkey::find_program_address(&[b"vault", user.as_ref()], &program_id);
    let deposit_amount: u64 = 100_000_000;
    let ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(user, true),
            AccountMeta::new(vault_pda, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: {
            let mut data = vec![0u8];
            data.extend_from_slice(&deposit_amount.to_le_bytes());
            data
        },
    };
    let user_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let vault_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };
    let result = mollusk.process_instruction(
        &ix,
        &[
            (user, user_acc),
            (vault_pda, vault_acc),
            keyed_account_for_system_program(),
        ],
    );
    if result.program_result.is_err() {
        return Err(boxed_error(format!("vault execution failed: {:?}", result.program_result)));
    }
    print_cu("deposit", result.compute_units_consumed);
    Ok(())
}

fn probe_vault_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("vault-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, true)?;
    let user = Pubkey::new_unique();
    let (vault_pda, _bump) = Pubkey::find_program_address(&[b"vault", user.as_ref()], &program_id);
    let deposit_amount: u64 = 100_000_000;
    let ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(user, true),
            AccountMeta::new(vault_pda, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: {
            let mut data = vec![0u8];
            data.extend_from_slice(&deposit_amount.to_le_bytes());
            data
        },
    };
    let user_acc = Account { lamports: 1_000_000_000, ..Account::default() };
    let vault_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };
    let result = mollusk.process_instruction(&ix, &[(user, user_acc), (vault_pda, vault_acc), keyed_account_for_system_program()]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("vault-lazy execution failed: {:?}", result.program_result)));
    }
    print_cu("vault-lazy", result.compute_units_consumed);
    Ok(())
}

fn probe_transfer_sol(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("transfer-sol")?;
    let mollusk = load_mollusk(&program_id, artifact, true)?;
    let from = Pubkey::new_unique();
    let to = Pubkey::new_unique();
    let amount: u64 = 100_000_000;
    let ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(from, true),
            AccountMeta::new(to, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: amount.to_le_bytes().to_vec(),
    };
    let from_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let to_acc = Account::default();
    let result = mollusk.process_instruction(
        &ix,
        &[
            (from, from_acc),
            (to, to_acc),
            keyed_account_for_system_program(),
        ],
    );
    if result.program_result.is_err() {
        return Err(boxed_error(format!("transfer-sol execution failed: {:?}", result.program_result)));
    }
    print_cu("transfer", result.compute_units_consumed);
    Ok(())
}

fn probe_transfer_sol_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("transfer-sol-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, true)?;
    let from = Pubkey::new_unique();
    let to = Pubkey::new_unique();
    let amount: u64 = 100_000_000;
    let ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(from, true),
            AccountMeta::new(to, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: amount.to_le_bytes().to_vec(),
    };
    let from_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let to_acc = Account::default();
    let result = mollusk.process_instruction(
        &ix,
        &[
            (from, from_acc),
            (to, to_acc),
            keyed_account_for_system_program(),
        ],
    );
    if result.program_result.is_err() {
        return Err(boxed_error(format!("transfer-sol-lazy execution failed: {:?}", result.program_result)));
    }
    print_cu("transfer-sol-lazy", result.compute_units_consumed);
    Ok(())
}

fn probe_transfer_owned(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("transfer-owned")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let source = Pubkey::new_unique();
    let destination = Pubkey::new_unique();
    let source_lamports: u64 = 555_555;
    let destination_lamports: u64 = 890_875;

    let ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(source, false),
            AccountMeta::new(destination, false),
        ],
        data: source_lamports.to_le_bytes().to_vec(),
    };
    let source_acc = Account {
        lamports: source_lamports,
        data: vec![0],
        owner: program_id,
        executable: false,
        rent_epoch: 0,
    };
    let destination_acc = Account {
        lamports: destination_lamports,
        ..Account::default()
    };
    let result = mollusk.process_instruction(&ix, &[(source, source_acc), (destination, destination_acc)]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("transfer-owned execution failed: {:?}", result.program_result)));
    }
    print_cu("transfer-owned", result.compute_units_consumed);
    Ok(())
}

fn probe_transfer_owned_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("transfer-owned-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, false)?;
    let source = Pubkey::new_unique();
    let destination = Pubkey::new_unique();
    let source_lamports: u64 = 555_555;
    let destination_lamports: u64 = 890_875;

    let ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(source, false),
            AccountMeta::new(destination, false),
        ],
        data: source_lamports.to_le_bytes().to_vec(),
    };
    let source_acc = Account {
        lamports: source_lamports,
        data: vec![0],
        owner: program_id,
        executable: false,
        rent_epoch: 0,
    };
    let destination_acc = Account {
        lamports: destination_lamports,
        ..Account::default()
    };
    let result = mollusk.process_instruction(&ix, &[(source, source_acc), (destination, destination_acc)]);
    if result.program_result.is_err() {
        return Err(boxed_error(format!("transfer-owned-lazy execution failed: {:?}", result.program_result)));
    }
    print_cu("transfer-owned-lazy", result.compute_units_consumed);
    Ok(())
}

fn probe_pda_storage(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("pda-storage")?;
    let mollusk = load_mollusk(&program_id, artifact, true)?;
    let payer = Pubkey::new_unique();
    let user = Pubkey::new_unique();
    let (storage_pda, _bump) = Pubkey::find_program_address(&[STORAGE_SEED, user.as_ref()], &program_id);
    let initial_value: u64 = 42;

    let init_ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(payer, true),
            AccountMeta::new(storage_pda, false),
            AccountMeta::new(user, true),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: {
            let mut data = vec![0u8];
            data.extend_from_slice(&initial_value.to_le_bytes());
            data
        },
    };
    let payer_acc = Account {
        lamports: 2_000_000_000,
        ..Account::default()
    };
    let storage_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };
    let user_acc = Account {
        lamports: 1_000_000,
        ..Account::default()
    };
    let init_result = mollusk.process_instruction(
        &init_ix,
        &[
            (payer, payer_acc),
            (storage_pda, storage_acc),
            (user, user_acc),
            keyed_account_for_system_program(),
        ],
    );
    if init_result.program_result.is_err() {
        return Err(boxed_error(format!("pda-storage init failed: {:?}", init_result.program_result)));
    }
    print_cu("init", init_result.compute_units_consumed);

    let update_ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(storage_pda, false),
            AccountMeta::new(user, true),
        ],
        data: {
            let mut data = vec![1u8];
            data.extend_from_slice(&100u64.to_le_bytes());
            data
        },
    };
    let update_result = mollusk.process_instruction(
        &update_ix,
        &[
            (storage_pda, init_result.resulting_accounts[1].1.clone()),
            (user, init_result.resulting_accounts[2].1.clone()),
        ],
    );
    if update_result.program_result.is_err() {
        return Err(boxed_error(format!("pda-storage update failed: {:?}", update_result.program_result)));
    }
    print_cu("update", update_result.compute_units_consumed);
    Ok(())
}

fn probe_pda_storage_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("pda-storage-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, true)?;
    let payer = Pubkey::new_unique();
    let user = Pubkey::new_unique();
    let (storage_pda, _bump) = Pubkey::find_program_address(&[STORAGE_SEED, user.as_ref()], &program_id);
    let initial_value: u64 = 42;
    let init_ix = Instruction {
        program_id,
        accounts: vec![AccountMeta::new(payer, true), AccountMeta::new(storage_pda, false), AccountMeta::new(user, true), AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false)],
        data: { let mut data = vec![0u8]; data.extend_from_slice(&initial_value.to_le_bytes()); data },
    };
    let init_result = mollusk.process_instruction(&init_ix, &[(payer, Account { lamports: 2_000_000_000, ..Account::default() }), (storage_pda, Account { lamports: 0, data: vec![], owner: SYSTEM_PROGRAM_ID, executable: false, rent_epoch: 0 }), (user, Account { lamports: 1_000_000, ..Account::default() }), keyed_account_for_system_program()]);
    if init_result.program_result.is_err() { return Err(boxed_error(format!("pda-storage-lazy init failed: {:?}", init_result.program_result))); }
    print_cu("pda-storage-lazy-init", init_result.compute_units_consumed);
    let update_ix = Instruction { program_id, accounts: vec![AccountMeta::new(storage_pda, false), AccountMeta::new(user, true)], data: { let mut data = vec![1u8]; data.extend_from_slice(&100u64.to_le_bytes()); data } };
    let update_result = mollusk.process_instruction(&update_ix, &[(storage_pda, init_result.resulting_accounts[1].1.clone()), (user, init_result.resulting_accounts[2].1.clone())]);
    if update_result.program_result.is_err() { return Err(boxed_error(format!("pda-storage-lazy update failed: {:?}", update_result.program_result))); }
    print_cu("pda-storage-lazy-update", update_result.compute_units_consumed);
    Ok(())
}

fn probe_escrow(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("escrow")?;
    let mollusk = load_mollusk(&program_id, artifact, true)?;
    let maker = Pubkey::new_unique();
    let taker = Pubkey::new_unique();
    let (escrow_pda, _bump) = Pubkey::find_program_address(&[ESCROW_SEED, maker.as_ref()], &program_id);
    let amount: u64 = 100_000_000;

    let make_data = {
        let mut data = vec![0u8];
        data.extend_from_slice(taker.as_ref());
        data.extend_from_slice(&amount.to_le_bytes());
        data
    };
    let make_ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(maker, true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: make_data,
    };
    let maker_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let escrow_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };
    let make_result = mollusk.process_instruction(
        &make_ix,
        &[
            (maker, maker_acc.clone()),
            (escrow_pda, escrow_acc),
            keyed_account_for_system_program(),
        ],
    );
    if make_result.program_result.is_err() {
        return Err(boxed_error(format!("escrow make failed: {:?}", make_result.program_result)));
    }
    print_cu("make", make_result.compute_units_consumed);

    let accept_ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(taker, true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new(maker, false),
        ],
        data: vec![1u8],
    };
    let taker_acc = Account {
        lamports: 1_000_000,
        ..Account::default()
    };
    let accept_result = mollusk.process_instruction(
        &accept_ix,
        &[
            (taker, taker_acc),
            (escrow_pda, make_result.resulting_accounts[1].1.clone()),
            (maker, make_result.resulting_accounts[0].1.clone()),
        ],
    );
    if accept_result.program_result.is_err() {
        return Err(boxed_error(format!("escrow accept failed: {:?}", accept_result.program_result)));
    }
    print_cu("accept", accept_result.compute_units_consumed);

    let refund_seed_maker = Pubkey::new_unique();
    let refund_seed_taker = Pubkey::new_unique();
    let (refund_escrow_pda, _refund_bump) = Pubkey::find_program_address(&[ESCROW_SEED, refund_seed_maker.as_ref()], &program_id);
    let refund_make_data = {
        let mut data = vec![0u8];
        data.extend_from_slice(refund_seed_taker.as_ref());
        data.extend_from_slice(&amount.to_le_bytes());
        data
    };
    let refund_make_ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(refund_seed_maker, true),
            AccountMeta::new(refund_escrow_pda, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: refund_make_data,
    };
    let refund_make_result = mollusk.process_instruction(
        &refund_make_ix,
        &[
            (refund_seed_maker, maker_acc),
            (refund_escrow_pda, Account {
                lamports: 0,
                data: vec![],
                owner: SYSTEM_PROGRAM_ID,
                executable: false,
                rent_epoch: 0,
            }),
            keyed_account_for_system_program(),
        ],
    );
    if refund_make_result.program_result.is_err() {
        return Err(boxed_error(format!("escrow refund setup failed: {:?}", refund_make_result.program_result)));
    }

    let refund_ix = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(refund_seed_maker, true),
            AccountMeta::new(refund_escrow_pda, false),
        ],
        data: vec![2u8],
    };
    let refund_result = mollusk.process_instruction(
        &refund_ix,
        &[
            (refund_seed_maker, refund_make_result.resulting_accounts[0].1.clone()),
            (refund_escrow_pda, refund_make_result.resulting_accounts[1].1.clone()),
        ],
    );
    if refund_result.program_result.is_err() {
        return Err(boxed_error(format!("escrow refund failed: {:?}", refund_result.program_result)));
    }
    print_cu("refund", refund_result.compute_units_consumed);
    Ok(())
}

fn probe_escrow_lazy(artifact: &Path) -> Result<(), Box<dyn Error>> {
    let program_id = program_id_for("escrow-lazy")?;
    let mollusk = load_mollusk(&program_id, artifact, true)?;
    let maker = Pubkey::new_unique();
    let taker = Pubkey::new_unique();
    let (escrow_pda, _bump) = Pubkey::find_program_address(&[ESCROW_SEED, maker.as_ref()], &program_id);
    let amount: u64 = 100_000_000;
    let make_ix = Instruction {
        program_id,
        accounts: vec![AccountMeta::new(maker, true), AccountMeta::new(escrow_pda, false), AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false)],
        data: { let mut data = vec![0u8]; data.extend_from_slice(taker.as_ref()); data.extend_from_slice(&amount.to_le_bytes()); data },
    };
    let make_result = mollusk.process_instruction(&make_ix, &[(maker, Account { lamports: 1_000_000_000, ..Account::default() }), (escrow_pda, Account { lamports: 0, data: vec![], owner: SYSTEM_PROGRAM_ID, executable: false, rent_epoch: 0 }), keyed_account_for_system_program()]);
    if make_result.program_result.is_err() { return Err(boxed_error(format!("escrow-lazy make failed: {:?}", make_result.program_result))); }
    print_cu("escrow-lazy-make", make_result.compute_units_consumed);
    let accept_ix = Instruction { program_id, accounts: vec![AccountMeta::new(taker, true), AccountMeta::new(escrow_pda, false), AccountMeta::new(maker, false)], data: vec![1u8] };
    let accept_result = mollusk.process_instruction(&accept_ix, &[(taker, Account { lamports: 1_000_000, ..Account::default() }), (escrow_pda, make_result.resulting_accounts[1].1.clone()), (maker, make_result.resulting_accounts[0].1.clone())]);
    if accept_result.program_result.is_err() { return Err(boxed_error(format!("escrow-lazy accept failed: {:?}", accept_result.program_result))); }
    print_cu("escrow-lazy-accept", accept_result.compute_units_consumed);
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let mut example = String::new();
    let mut artifact = String::new();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--example" => example = args.next().ok_or_else(|| boxed_error(usage()))?,
            "--artifact" => artifact = args.next().ok_or_else(|| boxed_error(usage()))?,
            "-h" | "--help" => {
                println!("{}", usage());
                return Ok(());
            }
            other => return Err(boxed_error(format!("unexpected argument: {other}\n{}", usage()))),
        }
    }

    if example.is_empty() || artifact.is_empty() {
        return Err(boxed_error(usage()));
    }

    let artifact_path = Path::new(&artifact);
    if !artifact_path.exists() {
        return Err(boxed_error(format!("artifact not found: {}", artifact_path.display())));
    }

    match example.as_str() {
        "hello" => probe_hello(artifact_path)?,
        "hello-lazy" => probe_hello_lazy(artifact_path)?,
        "noop" => probe_noop(artifact_path)?,
        "noop-lazy" => probe_noop_lazy(artifact_path)?,
        "logonly" => probe_logonly(artifact_path)?,
        "logonly-lazy" => probe_logonly_lazy(artifact_path)?,
        "counter" => probe_counter(artifact_path)?,
        "counter-lazy" => probe_counter_lazy(artifact_path)?,
        "vault" => probe_vault(artifact_path)?,
        "vault-lazy" => probe_vault_lazy(artifact_path)?,
        "transfer-sol" => probe_transfer_sol(artifact_path)?,
        "transfer-sol-lazy" => probe_transfer_sol_lazy(artifact_path)?,
        "transfer-owned" => probe_transfer_owned(artifact_path)?,
        "transfer-owned-lazy" => probe_transfer_owned_lazy(artifact_path)?,
        "pda-storage" => probe_pda_storage(artifact_path)?,
        "pda-storage-lazy" => probe_pda_storage_lazy(artifact_path)?,
        "escrow" => probe_escrow(artifact_path)?,
        "escrow-lazy" => probe_escrow_lazy(artifact_path)?,
        _ => return Err(boxed_error(format!("unsupported example for CU probing: {example}"))),
    }

    Ok(())
}
