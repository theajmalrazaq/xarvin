use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use regex::Regex;
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::process::{Child, ChildStdin, Command};
use tokio::sync::{mpsc, Mutex, Notify, RwLock};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct StatePayload {
    pub status: String,
    pub tool: String,
    pub message: String,
    pub active: bool,
    pub always_listening: bool,
    pub timestamp: f64,
}

#[derive(Clone)]
#[allow(dead_code)]
struct Config {
    runtime_dir: PathBuf,
    socket_path: PathBuf,
    state_path: PathBuf,
    pid_path: PathBuf,
    env_path: PathBuf,
    agy_bin: String,
    piper_python: String,
    piper_script: String,
}

impl Config {
    fn load() -> Self {
        let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })));
        let socket_path = runtime_dir.join("xarvin.sock");
        let state_path = runtime_dir.join("xarvin-state.json");
        let pid_path = runtime_dir.join("xarvin-server.pid");
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/theajmalrazaq".to_string());
        let env_path = std::env::var("XARVIN_ENV").map(PathBuf::from).unwrap_or_else(|_| {
            let p1 = PathBuf::from(&home).join("Projects/xarvin/config/xarvin.env");
            if p1.exists() {
                p1
            } else {
                PathBuf::from(&home).join(".config/xarvin/xarvin.env")
            }
        });

        let agy_bin = std::env::var("AGY_BIN").unwrap_or_else(|_| {
            let local = format!("{}/.local/bin/agy", home);
            if Path::new(&local).exists() {
                local
            } else {
                "agy".to_string()
            }
        });

        let piper_python = std::env::var("XARVIN_PYTHON").unwrap_or_else(|_| {
            let p1 = format!("{}/Projects/xarvin/.venv/bin/python3", home);
            if Path::new(&p1).exists() {
                p1
            } else {
                format!("{}/.config/xarvin/.venv/bin/python3", home)
            }
        });

        let piper_script = std::env::var("XARVIN_TTS_SCRIPT").unwrap_or_else(|_| {
            let p1 = format!("{}/Projects/xarvin/tts/xarvin_tts_worker.py", home);
            if Path::new(&p1).exists() {
                p1
            } else {
                format!("{}/.config/xarvin/tts/xarvin_tts_worker.py", home)
            }
        });

        Config {
            runtime_dir,
            socket_path,
            state_path,
            pid_path,
            env_path,
            agy_bin,
            piper_python,
            piper_script,
        }
    }
}

// Write status atomically to $XDG_RUNTIME_DIR/xarvin-state.json
fn write_state(cfg: &Config, status: &str, tool: &str, message: &str) {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64();
    let payload = StatePayload {
        status: status.to_string(),
        tool: tool.to_string(),
        message: message.to_string(),
        active: status != "idle",
        always_listening: false,
        timestamp: now,
    };
    if let Ok(json_str) = serde_json::to_string(&payload) {
        // Direct write preserves file inode so inotify / FileView always receives IN_MODIFY
        let _ = std::fs::write(&cfg.state_path, json_str.as_bytes());
        let legacy_state = cfg.runtime_dir.join("jarvis-state.json");
        let _ = std::fs::write(&legacy_state, json_str.as_bytes());
    }
}

// ---------------------------------------------------------------------------
// Resident TTS Worker Handler
// ---------------------------------------------------------------------------
#[allow(dead_code)]
struct PiperWorker {
    stdin: ChildStdin,
    reader: BufReader<tokio::process::ChildStdout>,
    child: Child,
}

impl PiperWorker {
    async fn start(cfg: &Config) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let mut cmd = Command::new(&cfg.piper_python);
        cmd.arg(&cfg.piper_script)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::inherit());

        let mut child = cmd.spawn()?;
        let stdin = child.stdin.take().ok_or("Failed to open worker stdin")?;
        let stdout = child.stdout.take().ok_or("Failed to open worker stdout")?;
        let mut reader = BufReader::new(stdout);

        // Wait for ready event
        let mut line = String::new();
        reader.read_line(&mut line).await?;
        eprintln!("[TTS] Worker ready: {}", line.trim());

        Ok(Self {
            stdin,
            reader,
            child,
        })
    }

    async fn speak(&mut self, text: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let req = serde_json::json!({
            "cmd": "speak",
            "text": text
        });
        self.stdin
            .write_all(format!("{}\n", serde_json::to_string(&req)?).as_bytes())
            .await?;
        self.stdin.flush().await?;

        // Read responses until "done"
        loop {
            let mut line = String::new();
            if self.reader.read_line(&mut line).await? == 0 {
                break;
            }
            if let Ok(ev) = serde_json::from_str::<serde_json::Value>(line.trim()) {
                if ev.get("event").and_then(|s| s.as_str()) == Some("done") {
                    break;
                }
            }
        }
        Ok(())
    }

    async fn stop(&mut self) {
        let req = serde_json::json!({"cmd": "stop"});
        if let Ok(s) = serde_json::to_string(&req) {
            let _ = self.stdin.write_all(format!("{}\n", s).as_bytes()).await;
            let _ = self.stdin.flush().await;
        }
    }

    async fn wait_playback(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let req = serde_json::json!({"cmd": "wait"});
        self.stdin
            .write_all(format!("{}\n", serde_json::to_string(&req)?).as_bytes())
            .await?;
        self.stdin.flush().await?;

        loop {
            let mut line = String::new();
            if self.reader.read_line(&mut line).await? == 0 {
                break;
            }
            if let Ok(ev) = serde_json::from_str::<serde_json::Value>(line.trim()) {
                if ev.get("event").and_then(|s| s.as_str()) == Some("done") {
                    break;
                }
            }
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Resident Warm Antigravity Process Session
// ---------------------------------------------------------------------------
struct AgySession {
    child: Option<Child>,
    stdin: Option<ChildStdin>,
    rx: mpsc::Receiver<serde_json::Value>,
    agy_bin: String,
}

impl AgySession {
    async fn new(agy_bin: &str) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let (tx, rx) = mpsc::channel::<serde_json::Value>(100);
        let mut sess = Self {
            child: None,
            stdin: None,
            rx,
            agy_bin: agy_bin.to_string(),
        };
        sess.spawn_process(tx).await?;
        Ok(sess)
    }

    async fn spawn_process(
        &mut self,
        tx: mpsc::Sender<serde_json::Value>,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut cmd = Command::new(&self.agy_bin);
        cmd.args([
            "--dangerously-skip-permissions",
            "--disable-slash-commands",
            "--model",
            "gemini-3.8-flash-low",
            "--effort",
            "low",
            "--input-format",
            "stream-json",
            "--output-format",
            "stream-json",
            "-p=",
        ]);
        cmd.stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::inherit());

        let mut child = cmd.spawn()?;
        let stdin = child.stdin.take().ok_or("Failed to open agy stdin")?;
        let stdout = child.stdout.take().ok_or("Failed to open agy stdout")?;

        self.child = Some(child);
        self.stdin = Some(stdin);

        tokio::spawn(async move {
            let mut lines = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(trimmed) {
                    let _ = tx.send(val).await;
                }
            }
            eprintln!("[AGY] Stream reader ended");
        });

        Ok(())
    }

    async fn ensure_alive(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let is_dead = match &mut self.child {
            Some(c) => c.try_wait()?.is_some(),
            None => true,
        };
        if is_dead {
            eprintln!("[AGY] Process died, respawning...");
            let (tx, rx) = mpsc::channel::<serde_json::Value>(100);
            self.rx = rx;
            self.spawn_process(tx).await?;
            let _ = self.warmup().await;
        }
        Ok(())
    }

    async fn warmup(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let warmup_msg = serde_json::json!({
            "event": "user",
            "message": {
                "content": "Warmup ping. Reply with OK."
            }
        });
        if let Some(stdin) = self.stdin.as_mut() {
            let data = serde_json::to_string(&warmup_msg)?;
            stdin.write_all(format!("{}\n", data).as_bytes()).await?;
            stdin.flush().await?;
        }

        let timeout = tokio::time::sleep(Duration::from_secs(12));
        tokio::pin!(timeout);

        loop {
            tokio::select! {
                ev_opt = self.rx.recv() => {
                    if let Some(ev) = ev_opt {
                        if ev.get("event").and_then(|s| s.as_str()) == Some("result") {
                            eprintln!("[AGY] Warmup complete. System ready and cached.");
                            break;
                        }
                    } else {
                        break;
                    }
                }
                _ = &mut timeout => {
                    eprintln!("[AGY] Warmup timed out, continuing...");
                    break;
                }
            }
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Daemon State
// ---------------------------------------------------------------------------
struct DaemonState {
    cfg: Config,
    status: RwLock<String>,
    cancel_flag: Arc<AtomicBool>,
    finish_listen_notify: Arc<Notify>,
    piper: Mutex<PiperWorker>,
    agy: Mutex<AgySession>,
}

impl DaemonState {
    async fn set_status(&self, st: &str, tool: &str, msg: &str) {
        let mut w = self.status.write().await;
        *w = st.to_string();
        write_state(&self.cfg, st, tool, msg);
    }

    async fn cancel_activity(&self) {
        self.cancel_flag.store(true, Ordering::Relaxed);
        self.finish_listen_notify.notify_waiters();
        let mut piper = self.piper.lock().await;
        piper.stop().await;
        self.set_status("idle", "", "").await;
    }
}

fn format_tool_name(raw: &str) -> String {
    let lower = raw.to_lowercase();
    if lower.contains("octopus") {
        "WhatsApp".to_string()
    } else if lower.contains("composio") {
        "Composio".to_string()
    } else if lower.contains("brief") {
        "System Brief".to_string()
    } else if lower.contains("bash") || lower.contains("run_command") {
        "System Command".to_string()
    } else if lower.contains("file") {
        "File System".to_string()
    } else {
        raw.replace('_', " ")
    }
}

// ---------------------------------------------------------------------------
// Text Turn Pipeline Worker (Notch Input -> AGY -> Talks Back Out Loud)
// ---------------------------------------------------------------------------
async fn run_text_turn(state: Arc<DaemonState>, text: String) {
    if text.trim().is_empty() {
        return;
    }
    state.cancel_flag.store(false, Ordering::Relaxed);
    eprintln!("[USER:NOTCH] {}", text);

    // 1. Pipelined TTS Speech Queue
    let (speech_tx, mut speech_rx) = mpsc::channel::<String>(50);
    let state_tts = state.clone();

    let tts_handle = tokio::spawn(async move {
        while let Some(sentence) = speech_rx.recv().await {
            if state_tts.cancel_flag.load(Ordering::Relaxed) {
                break;
            }
            eprintln!("[VOICE:START] speaking: {}", sentence);
            state_tts.set_status("speaking", "", &sentence).await;
            let mut piper = state_tts.piper.lock().await;
            let _ = piper.speak(&sentence).await;
            eprintln!("[VOICE:DONE] finished sentence: {}", sentence);
        }
        if !state_tts.cancel_flag.load(Ordering::Relaxed) {
            let mut piper = state_tts.piper.lock().await;
            let _ = piper.wait_playback().await;
        }
    });

    // 2. Send to Persistent Warm Agy Process
    state.set_status("thinking", "", "Thinking...").await;

    let prompt = format!(
        "{}\n\n[Voice Mode: Your name is XARVIN. You are a sharp, casual, and friendly AI companion. Talk naturally and casually — strictly NEVER say 'sir', 'master', or use formal honorifics. Speak exclusively in English with a relaxed, modern conversational tone. Never use markdown, bullets, asterisks, emoji, or lists. Keep your spoken response to 1-2 concise, natural sentences. For general app actions, integrations, and tools, always use Composio MCP (`composio` tools). For WhatsApp messaging, contacts, groups, or status, always use Octopus MCP (`octopus` tools like `octopus_send_message`, `octopus_list_contacts`, `octopus_status`). For 'system brief', run `python3 ~/.gemini/config/skills/brief/scripts/system_brief.py`. For 'news brief', run `python3 ~/.gemini/config/skills/brief/scripts/news_brief.py`. For 'today brief', run `python3 ~/.gemini/config/skills/brief/scripts/today_brief.py`. Always execute tools or MCP actions immediately and casually report what happened.]",
        text
    );

    let user_msg = serde_json::json!({
        "event": "user",
        "message": {
            "content": prompt
        }
    });

    let mut agy = state.agy.lock().await;
    let _ = agy.ensure_alive().await;
    if let Some(stdin) = agy.stdin.as_mut() {
        if let Ok(data) = serde_json::to_string(&user_msg) {
            let _ = stdin.write_all(format!("{}\n", data).as_bytes()).await;
            let _ = stdin.flush().await;
        }
    }

    let sentence_re = Regex::new(r"^([\s\S]+?[.!?])(?:\s+|$)").unwrap();
    let mut streamed_text = String::new();
    let mut spoken_upto = 0;
    let mut spoken_count = 0;
    let mut final_response = String::new();

    while !state.cancel_flag.load(Ordering::Relaxed) {
        tokio::select! {
            ev_opt = agy.rx.recv() => {
                match ev_opt {
                    Some(ev) => {
                        let etype = ev.get("event").and_then(|s| s.as_str()).unwrap_or("");
                        if etype == "step_update" {
                            if let Some(su) = ev.get("step_update") {
                                let stype = su.get("step_type").and_then(|s| s.as_str()).unwrap_or("");
                                let step_state = su.get("state").and_then(|s| s.as_str()).unwrap_or("");

                                if stype == "tool" {
                                    if step_state == "ACTIVE" || step_state == "RUNNING" {
                                        let tool_name = su.get("tool_name").and_then(|s| s.as_str()).unwrap_or("tool");
                                        let formatted = format_tool_name(tool_name);
                                        eprintln!("[NOTCH:TOOL] {}", formatted);
                                        state.set_status("working", &formatted, "Executing action...").await;
                                    } else if step_state == "COMPLETED" || step_state == "DONE" {
                                        state.set_status("thinking", "", "Processing results...").await;
                                    }
                                } else if stype == "thought" || stype == "thinking" {
                                    if let Some(th) = su.get("thought").or_else(|| su.get("text_delta")).and_then(|s| s.as_str()) {
                                        let trimmed = th.trim();
                                        if !trimmed.is_empty() {
                                            state.set_status("thinking", "", trimmed).await;
                                        }
                                    }
                                } else if stype == "agent_response" {
                                    if let Some(delta) = su.get("text_delta").and_then(|s| s.as_str()) {
                                        streamed_text.push_str(delta);

                                        while let Some(captures) = sentence_re.captures(&streamed_text[spoken_upto..]) {
                                            if let Some(mat) = captures.get(1) {
                                                let s = mat.as_str().trim();
                                                if !s.is_empty() {
                                                    spoken_upto += mat.end();
                                                    spoken_count += 1;
                                                    eprintln!("[NOTCH:TTS:ENQUEUE] {}", s);
                                                    let _ = speech_tx.send(s.to_string()).await;
                                                    continue;
                                                }
                                            }
                                            break;
                                        }
                                    }
                                }
                            }
                        } else if etype == "result" {
                            if let Some(res) = ev.get("result") {
                                if let Some(content) = res.get("content").and_then(|s| s.as_str()) {
                                    final_response = content.trim().to_string();
                                }
                            }
                            break;
                        }
                    }
                    None => break,
                }
            }
            _ = tokio::time::sleep(Duration::from_millis(100)) => {
                if state.cancel_flag.load(Ordering::Relaxed) {
                    break;
                }
            }
        }
    }

    drop(agy);

    // Speak any remaining text
    let full_text = if !final_response.is_empty() {
        final_response
    } else {
        streamed_text
    };

    eprintln!("[NOTCH:RESULT] {}", full_text);

    if spoken_upto < full_text.len() {
        let remainder = full_text[spoken_upto..].trim();
        if !remainder.is_empty() {
            spoken_count += 1;
            let _ = speech_tx.send(remainder.to_string()).await;
        }
    }

    if spoken_count == 0 && !state.cancel_flag.load(Ordering::Relaxed) {
        if !full_text.is_empty() {
            let _ = speech_tx.send(full_text).await;
        }
    }

    // Close speech queue and wait for playback to complete
    drop(speech_tx);
    let _ = tts_handle.await;

    if !state.cancel_flag.load(Ordering::Relaxed) {
        state.set_status("idle", "", "").await;
    }
}

// ---------------------------------------------------------------------------
// Main Daemon Server Loop
// ---------------------------------------------------------------------------
async fn run_daemon(cfg: Config) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let _ = std::fs::remove_file(&cfg.socket_path);

    // Save PID
    let pid = std::process::id();
    let _ = std::fs::write(&cfg.pid_path, format!("{}", pid));

    // Initial state: idle
    write_state(&cfg, "idle", "", "");

    eprintln!("[DAEMON] Initializing resident TTS worker...");
    let piper = PiperWorker::start(&cfg).await?;

    eprintln!("[DAEMON] Initializing warm Antigravity CLI session...");
    let mut agy = AgySession::new(&cfg.agy_bin).await?;
    let _ = agy.warmup().await;

    let state = Arc::new(DaemonState {
        cfg: cfg.clone(),
        status: RwLock::new("idle".to_string()),
        cancel_flag: Arc::new(AtomicBool::new(false)),
        finish_listen_notify: Arc::new(Notify::new()),
        piper: Mutex::new(piper),
        agy: Mutex::new(agy),
    });

    let listener = UnixListener::bind(&cfg.socket_path)?;
    let legacy_sock = cfg.runtime_dir.join("jarvis.sock");
    let _ = std::fs::remove_file(&legacy_sock);
    let _ = std::os::unix::fs::symlink(&cfg.socket_path, &legacy_sock);
    eprintln!("[DAEMON] Listening on {}", cfg.socket_path.display());

    loop {
        match listener.accept().await {
            Ok((mut stream, _)) => {
                let mut buf = [0u8; 4096];
                let n = match stream.read(&mut buf).await {
                    Ok(n) if n > 0 => n,
                    _ => continue,
                };
                let cmd = String::from_utf8_lossy(&buf[..n]).trim().to_string();

                if cmd.starts_with("ask ") {
                    let prompt_text = cmd[4..].trim().to_string();
                    let cur = { state.status.read().await.clone() };
                    if cur != "idle" {
                        state.cancel_activity().await;
                        tokio::time::sleep(Duration::from_millis(50)).await;
                    }
                    let s = state.clone();
                    tokio::spawn(async move {
                        run_text_turn(s, prompt_text).await;
                    });
                } else {
                    match cmd.as_str() {
                        "toggle" | "toggle-listen" | "voice" => {
                            let cur = { state.status.read().await.clone() };
                            if cur != "idle" {
                                state.cancel_activity().await;
                            } else {
                                let _ = Command::new("qs")
                                    .args(["-c", "xarvin", "ipc", "call", "xarvin", "toggle"])
                                    .spawn();
                            }
                        }
                        "stop" => {
                            state.cancel_activity().await;
                        }
                        "ping" => {
                            let _ = stream.write_all(b"pong\n").await;
                        }
                        "status" => {
                            let cur = { state.status.read().await.clone() };
                            let _ = stream.write_all(format!("status: {}\n", cur).as_bytes()).await;
                        }
                        _ => {}
                    }
                }
            }
            Err(e) => {
                eprintln!("[DAEMON] Accept error: {}", e);
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// CLI Client Mode
// ---------------------------------------------------------------------------
async fn send_client_command(cfg: &Config, cmd: &str) -> Result<(), Box<dyn std::error::Error>> {
    let mut stream = UnixStream::connect(&cfg.socket_path).await?;
    stream.write_all(cmd.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Entry Point
// ---------------------------------------------------------------------------
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cfg = Config::load();
    let args: Vec<String> = std::env::args().collect();

    if args.len() == 1 || (args.len() > 1 && (args[1] == "notch" || args[1] == "prompt")) {
        let _ = Command::new("qs")
            .args(["-c", "xarvin", "ipc", "call", "xarvin", "toggle"])
            .spawn();
        return Ok(());
    }

    if args.len() > 1 && args[1] != "daemon" && args[1] != "--daemon" && args[1] != "server" {
        let cmd = if args[1] == "ask" {
            let prompt = args[2..].join(" ");
            format!("ask {}", prompt)
        } else {
            args[1].clone()
        };
        if let Err(_) = send_client_command(&cfg, &cmd).await {
            if cmd == "toggle" || cmd == "restart" || cmd == "voice" {
                let current_exe = std::env::current_exe()?;
                Command::new(current_exe)
                    .arg("daemon")
                    .stdin(std::process::Stdio::null())
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .spawn()?;
                tokio::time::sleep(Duration::from_millis(400)).await;
                let _ = send_client_command(&cfg, &cmd).await;
            }
        }
        return Ok(());
    }

    if let Err(e) = run_daemon(cfg).await {
        eprintln!("[DAEMON] Fatal error: {}", e);
    }
    Ok(())
}
