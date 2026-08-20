// Placeholder - Checkpoint 5: CLI binary with clap subcommands
// Commands: validate, convert-webp, merge, cbr-to-cbz

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();
}
