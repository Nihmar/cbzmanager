use std::sync::Mutex;
use crossbeam_channel as channel;
use std::time::Instant;

/// A single log entry.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct LogEntry {
    pub level: String,
    pub message: String,
    pub timestamp: String,
}

/// Thread-safe log buffer that accumulates entries and allows the
/// frontend to pull them (via Tauri events or polling commands).
pub struct LogBuffer {
    tx: Mutex<channel::Sender<String>>,
    rx: Mutex<Option<channel::Receiver<String>>>,
    start: Instant,
}

impl Clone for LogBuffer {
    fn clone(&self) -> Self {
        Self {
            tx: Mutex::new(self.tx.lock().unwrap().clone()),
            rx: Mutex::new(None), // Clone discards receiver — sender handles fan-out
            start: self.start,
        }
    }
}

impl LogBuffer {
    pub fn new() -> Self {
        let (tx, rx) = channel::bounded::<String>(256);
        Self {
            tx: Mutex::new(tx),
            rx: Mutex::new(Some(rx)),
            start: Instant::now(),
        }
    }

    /// Push a log message from any thread.
    pub fn push(&self, level: &str, message: &str) {
        let elapsed = self.start.elapsed();
        let secs = elapsed.as_secs_f32();
        let entry = format!(
            "{{\"level\":\"{}\",\"message\":\"{}\",\"timestamp\":{:.1}}}",
            level, message.replace('"', "\\\""), secs
        );
        if let Ok(tx) = self.tx.lock() {
            let _ = tx.send(entry);
        }
    }

    /// Drain all pending entries and return them as LogEntry structs.
    pub fn drain(&self) -> Vec<LogEntry> {
        let mut result = Vec::new();
        if let Ok(rx) = self.rx.lock() {
            if let Some(receiver) = rx.as_ref() {
                while let Ok(s) = receiver.try_recv() {
                    if let Ok(entry) = serde_json::from_str::<LogEntry>(&s) {
                        result.push(entry);
                    } else {
                        // Legacy format: try raw string.
                        result.push(LogEntry {
                            level: "info".to_string(),
                            message: s,
                            timestamp: format!("{:.1}", self.start.elapsed().as_secs_f32()),
                        });
                    }
                }
            }
        }
        result
    }

    /// Get a reference for use in progress callbacks.
    pub fn get_emitter(&self) -> LogEmitter {
        LogEmitter { buffer: self.clone() }
    }
}

/// A closure-compatible emitter that writes to the log buffer.
#[derive(Clone)]
pub struct LogEmitter {
    buffer: LogBuffer,
}

impl LogEmitter {
    pub fn emit(&self, level: &str, message: &str) {
        self.buffer.push(level, message);
    }
}
