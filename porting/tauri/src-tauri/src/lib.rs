mod commands;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            // Log in debug mode
            #[cfg(debug_assertions)]
            {
                let _ = app;
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // Archive operations
            commands::archive::list_entries,
            commands::archive::read_entry,
            commands::archive::first_image,
            // Directory
            commands::directory::list_directory,
            // Settings
            commands::settings::load_settings,
            commands::settings::save_settings,
            // Services
            commands::validate::cmd_validate,
            commands::validate::cmd_validate_deep,
            commands::convert_webp::cmd_convert_webp,
            commands::merge::cmd_merge,
            commands::cbr_to_cbz::cmd_cbr_to_cbz,
            commands::comicinfo::cmd_scan_comicinfo,
            commands::comicinfo::cmd_remove_comicinfo,
            // Page editing
            commands::page_edit::page_load,
            commands::page_edit::page_save,
            // Batch editing
            commands::batch_edit::apply_batch_edit,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
