//! CBZ Manager — Tauri GUI frontend (Checkpoint 6).
//!
//! This crate provides the Tauri v2 application that wraps `rust-core`
//! functions and exposes them as IPC commands to a Svelte 4 frontend.

use tauri::Manager;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let _ = app;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![])
        .run(tauri::generate_context!())
        .expect("error while running tauri process");
}
