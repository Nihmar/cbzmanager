use std::path::PathBuf;
use std::sync::Mutex;

/// Application settings persisted via INI file (matching Pascal implementation).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AppSettings {
    pub max_webp_threads: u32,
    pub max_cbr_threads: u32,
    pub validate_threads: u32,
    pub window_width: f64,
    pub window_height: f64,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            max_webp_threads: 0,       // 0 = auto (CPU cores)
            max_cbr_threads: 0,
            validate_threads: 0,
            window_width: 1280.0,
            window_height: 860.0,
        }
    }
}

/// Load settings from INI file.
#[tauri::command]
pub fn load_settings() -> Result<AppSettings, String> {
    let settings_path = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("cbzmanager")
        .join("settings.ini");

    if !settings_path.exists() {
        return Ok(AppSettings::default());
    }

    let content = std::fs::read_to_string(&settings_path).map_err(|e| e.to_string())?;
    
    // Simple INI parsing for our settings
    let mut settings = AppSettings::default();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') || line.contains('=') == false {
            continue;
        }
        let (key, value) = line.split_once('=').unwrap();
        let key = key.trim();
        let value = value.trim();
        match key {
            "max_webp_threads" => if let Ok(v) = value.parse() { settings.max_webp_threads = v; }
            "max_cbr_threads" => if let Ok(v) = value.parse() { settings.max_cbr_threads = v; }
            "validate_threads" => if let Ok(v) = value.parse() { settings.validate_threads = v; }
            "window_width" => if let Ok(v) = value.parse() { settings.window_width = v; }
            "window_height" => if let Ok(v) = value.parse() { settings.window_height = v; }
            _ => {}
        }
    }
    
    Ok(settings)
}

/// Save settings to INI file.
#[tauri::command]
pub fn save_settings(settings: AppSettings) -> Result<(), String> {
    let config_dir = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("cbzmanager");
    std::fs::create_dir_all(&config_dir).map_err(|e| e.to_string())?;
    
    let settings_path = config_dir.join("settings.ini");
    let content = format!(
        "[general]\nmax_webp_threads = {}\nmax_cbr_threads = {}\nvalidate_threads = {}\nwindow_width = {}\nwindow_height = {}\n",
        settings.max_webp_threads,
        settings.max_cbr_threads,
        settings.validate_threads,
        settings.window_width,
        settings.window_height,
    );
    std::fs::write(&settings_path, content).map_err(|e| e.to_string())?;
    Ok(())
}
