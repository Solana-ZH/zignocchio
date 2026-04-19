//! SVM-level integration test for the Zignocchio Token Vault program under
//! solana-program-test.

use solana_program_test::{processor, ProgramTest};
use solana_sdk::{
    account::Account,
    instruction::{AccountMeta, Instruction},
    program_option::COption,
    program_pack::Pack,
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    system_program,
    sysvar,
    transaction::Transaction,
};
use spl_token::state::{Account as TokenAccount, AccountState, Mint};

const DEPOSIT: u8 = 0;
const WITHDRAW: u8 = 1;
const INITIALIZE: u8 = 2;
const TOKEN_ACCOUNT_RENT: u64 = 2_039_280;
const MINT_RENT: u64 = 1_461_600;

fn program_id() -> Pubkey {
    Pubkey::new_from_array([7u8; 32])
}

fn token_program_id() -> Pubkey {
    spl_token::id()
}

fn find_vault_pda(owner: &Pubkey, program_id: &Pubkey) -> (Pubkey, u8) {
    Pubkey::find_program_address(&[b"vault", owner.as_ref()], program_id)
}

fn make_mint_account(mint_authority: Pubkey, supply: u64, decimals: u8) -> Account {
    let mint = Mint {
        mint_authority: COption::Some(mint_authority),
        supply,
        decimals,
        is_initialized: true,
        freeze_authority: COption::None,
    };
    let mut data = vec![0u8; Mint::LEN];
    Mint::pack(mint, &mut data).expect("mint pack should succeed");

    Account {
        lamports: MINT_RENT,
        data,
        owner: token_program_id(),
        executable: false,
        rent_epoch: 0,
    }
}

fn make_token_account(mint: Pubkey, owner: Pubkey, amount: u64) -> Account {
    let token_account = TokenAccount {
        mint,
        owner,
        amount,
        delegate: COption::None,
        state: AccountState::Initialized,
        is_native: COption::None,
        delegated_amount: 0,
        close_authority: COption::None,
    };
    let mut data = vec![0u8; TokenAccount::LEN];
    TokenAccount::pack(token_account, &mut data).expect("token account pack should succeed");

    Account {
        lamports: TOKEN_ACCOUNT_RENT,
        data,
        owner: token_program_id(),
        executable: false,
        rent_epoch: 0,
    }
}

fn initialize_ix(vault_pda: Pubkey, mint: Pubkey, owner: Pubkey, program_id: Pubkey) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(vault_pda, false),
            AccountMeta::new_readonly(mint, false),
            AccountMeta::new(owner, true),
            AccountMeta::new_readonly(system_program::id(), false),
            AccountMeta::new_readonly(token_program_id(), false),
            AccountMeta::new_readonly(sysvar::rent::id(), false),
        ],
        data: vec![INITIALIZE],
    }
}

fn deposit_ix(
    user_token_account: Pubkey,
    vault_pda: Pubkey,
    owner: Pubkey,
    program_id: Pubkey,
    amount: u64,
) -> Instruction {
    let mut data = vec![DEPOSIT];
    data.extend_from_slice(&amount.to_le_bytes());
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(user_token_account, false),
            AccountMeta::new(vault_pda, false),
            AccountMeta::new_readonly(owner, true),
            AccountMeta::new_readonly(token_program_id(), false),
        ],
        data,
    }
}

fn withdraw_ix(vault_pda: Pubkey, user_token_account: Pubkey, owner: Pubkey, program_id: Pubkey) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(vault_pda, false),
            AccountMeta::new(user_token_account, false),
            AccountMeta::new_readonly(owner, true),
            AccountMeta::new_readonly(token_program_id(), false),
        ],
        data: vec![WITHDRAW],
    }
}

#[tokio::test]
async fn test_token_vault_initialize_deposit_withdraw() {
    let pid = program_id();
    let owner = Keypair::new();
    let mint = Keypair::new().pubkey();
    let user_token_account = Keypair::new().pubkey();
    let (vault_pda, _bump) = find_vault_pda(&owner.pubkey(), &pid);
    let deposit_amount: u64 = 500_000_000;

    let mut program_test = ProgramTest::default();
    program_test.prefer_bpf(false);
    program_test.add_program(
        "spl_token",
        token_program_id(),
        processor!(spl_token::processor::Processor::process),
    );
    program_test.prefer_bpf(true);
    program_test.add_program("token-vault", pid, None);
    program_test.add_account(
        owner.pubkey(),
        Account {
            lamports: 1_000_000_000,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );
    program_test.add_account(mint, make_mint_account(owner.pubkey(), 1_000_000_000, 9));
    program_test.add_account(
        user_token_account,
        make_token_account(mint, owner.pubkey(), 1_000_000_000),
    );

    let (banks_client, payer, recent_blockhash) = program_test.start().await;

    let init_ix = initialize_ix(vault_pda, mint, owner.pubkey(), pid);
    let mut init_tx = Transaction::new_with_payer(&[init_ix], Some(&payer.pubkey()));
    init_tx.sign(&[&payer, &owner], recent_blockhash);
    let init_result = banks_client.process_transaction(init_tx).await;
    assert!(init_result.is_ok(), "initialize should succeed: {:?}", init_result);

    let vault_after_init = banks_client
        .get_account(vault_pda)
        .await
        .expect("vault fetch after initialize should succeed")
        .expect("vault token account should exist after initialize");
    assert_eq!(vault_after_init.owner, token_program_id());
    let vault_state = TokenAccount::unpack(&vault_after_init.data).expect("vault token account should unpack");
    assert_eq!(vault_state.mint, mint);
    assert_eq!(vault_state.owner, vault_pda);
    assert_eq!(vault_state.amount, 0);

    let blockhash = banks_client
        .get_latest_blockhash()
        .await
        .expect("latest blockhash should be available after initialize");
    let deposit_ix = deposit_ix(user_token_account, vault_pda, owner.pubkey(), pid, deposit_amount);
    let mut deposit_tx = Transaction::new_with_payer(&[deposit_ix], Some(&payer.pubkey()));
    deposit_tx.sign(&[&payer, &owner], blockhash);
    let deposit_result = banks_client.process_transaction(deposit_tx).await;
    assert!(deposit_result.is_ok(), "deposit should succeed: {:?}", deposit_result);

    let user_after_deposit = banks_client
        .get_account(user_token_account)
        .await
        .expect("user token fetch after deposit should succeed")
        .expect("user token account should exist after deposit");
    let user_state = TokenAccount::unpack(&user_after_deposit.data).expect("user token account should unpack");
    assert_eq!(user_state.amount, 500_000_000);

    let vault_after_deposit = banks_client
        .get_account(vault_pda)
        .await
        .expect("vault fetch after deposit should succeed")
        .expect("vault token account should exist after deposit");
    let vault_state_after_deposit =
        TokenAccount::unpack(&vault_after_deposit.data).expect("vault token account should unpack after deposit");
    assert_eq!(vault_state_after_deposit.amount, deposit_amount);

    let blockhash = banks_client
        .get_latest_blockhash()
        .await
        .expect("latest blockhash should be available after deposit");
    let withdraw_ix = withdraw_ix(vault_pda, user_token_account, owner.pubkey(), pid);
    let mut withdraw_tx = Transaction::new_with_payer(&[withdraw_ix], Some(&payer.pubkey()));
    withdraw_tx.sign(&[&payer, &owner], blockhash);
    let withdraw_result = banks_client.process_transaction(withdraw_tx).await;
    assert!(withdraw_result.is_ok(), "withdraw should succeed: {:?}", withdraw_result);

    let user_after_withdraw = banks_client
        .get_account(user_token_account)
        .await
        .expect("user token fetch after withdraw should succeed")
        .expect("user token account should exist after withdraw");
    let user_state_after_withdraw =
        TokenAccount::unpack(&user_after_withdraw.data).expect("user token account should unpack after withdraw");
    assert_eq!(user_state_after_withdraw.amount, 1_000_000_000);

    let vault_after_withdraw = banks_client
        .get_account(vault_pda)
        .await
        .expect("vault fetch after withdraw should succeed")
        .expect("vault token account should exist after withdraw");
    let vault_state_after_withdraw = TokenAccount::unpack(&vault_after_withdraw.data)
        .expect("vault token account should unpack after withdraw");
    assert_eq!(vault_state_after_withdraw.amount, 0);
}
