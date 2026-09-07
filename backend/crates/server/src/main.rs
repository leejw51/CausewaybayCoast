mod db;
mod npc;
mod world;

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
    routing::get,
    Router,
};
use futures_util::{SinkExt, StreamExt};
use protocol::*;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;
use tracing::{info, warn};
use world::World;

type Shared = Arc<Mutex<World>>;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env().add_directive("server=info".parse()?),
        )
        .init();
    // Persistence lives in ~/.causewaybaycoast/server by default (override with COAST_DIR / COAST_DB).
    let data_dir = std::env::var("COAST_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
            std::path::Path::new(&home)
                .join(".causewaybaycoast")
                .join("server")
        });
    std::fs::create_dir_all(&data_dir)?;
    let db_path = std::env::var("COAST_DB")
        .unwrap_or_else(|_| data_dir.join("coast.db").to_string_lossy().into_owned());
    let events_path = data_dir.join("events.jsonl");
    let port: u16 = std::env::var("COAST_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(DEFAULT_PORT);
    if let Some(dir) = std::path::Path::new(&db_path).parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut db = db::Db::open(&db_path)?;
    db.seed_demo_friends()?;
    let world: Shared = Arc::new(Mutex::new(World::new(db, Some(&events_path))?));

    npc::run(world.clone());
    let app = Router::new()
        .route("/", get(|| async { "causeway bay coast server" }))
        .route("/health", get(|| async { "ok" }))
        .route("/ws", get(ws_handler))
        .with_state(world);

    let host = std::env::var("COAST_HOST").unwrap_or_else(|_| "127.0.0.1".into());
    let listener = tokio::net::TcpListener::bind((host.as_str(), port)).await?;
    info!(
        "listening on ws://{host}:{port}/ws  (db: {db_path}, events: {})",
        events_path.display()
    );
    axum::serve(listener, app).await?;
    Ok(())
}

async fn ws_handler(ws: WebSocketUpgrade, State(world): State<Shared>) -> impl IntoResponse {
    ws.max_message_size(16 * 1024)
        .max_frame_size(16 * 1024)
        .on_upgrade(move |socket| handle_socket(socket, world))
}

async fn handle_socket(socket: WebSocket, world: Shared) {
    let (mut sink, mut stream) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<ServerMsg>();

    // Outbound pump: serialize everything queued for this client.
    let writer = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            let text = serde_json::to_string(&msg).unwrap_or_default();
            if sink.send(Message::Text(text.into())).await.is_err() {
                break;
            }
        }
    });

    let mut pid: Option<i64> = None;
    while let Some(Ok(msg)) = stream.next().await {
        let text = match msg {
            Message::Text(t) => t.to_string(),
            Message::Close(_) => break,
            _ => continue,
        };
        let parsed: Result<ClientMsg, _> = serde_json::from_str(&text);
        let reply = match parsed {
            Err(e) => Some(ServerMsg::Error {
                message: format!("bad message: {e}"),
            }),
            Ok(cm) => handle(&world, &mut pid, &tx, cm),
        };
        if let Some(r) = reply {
            let _ = tx.send(r);
        }
    }
    if let Some(p) = pid {
        world.lock().unwrap().leave(p);
        info!("player {p} disconnected");
    }
    writer.abort();
}

fn handle(
    world: &Shared,
    pid: &mut Option<i64>,
    tx: &world::Tx,
    cm: ClientMsg,
) -> Option<ServerMsg> {
    let mut w = world.lock().unwrap();
    let err = |e: anyhow::Error| {
        Some(ServerMsg::Error {
            message: e.to_string(),
        })
    };
    if let ClientMsg::Hello { name, colour } = &cm {
        if pid.is_some() {
            return Some(ServerMsg::Error {
                message: "already logged in".into(),
            });
        }
        let name = name.trim();
        if name.is_empty() || name.len() > 24 || name.chars().any(char::is_control) {
            return Some(ServerMsg::Error {
                message: "name must be 1-24 chars".into(),
            });
        }
        if matches!(name, "Sunny (demo)" | "Marina (demo)") {
            return Some(ServerMsg::Error {
                message: "choose your own name; demo friends are reserved".into(),
            });
        }
        let colour = colour.clone().unwrap_or_else(|| "#ffcc66".into());
        return match w.join(name, &colour, tx.clone()) {
            Ok((id, room)) => {
                *pid = Some(id);
                info!("player {id} '{name}' joined room {}", room.id);
                Some(ServerMsg::Welcome {
                    player_id: id,
                    room,
                })
            }
            Err(e) => err(e),
        };
    }
    let Some(p) = *pid else {
        return Some(ServerMsg::Error {
            message: "send hello first".into(),
        });
    };
    match cm {
        ClientMsg::Hello { .. } => unreachable!(),
        ClientMsg::Move { x, y } => {
            w.move_to(p, x, y);
            None
        }
        ClientMsg::PlaceItem { kind, tx, ty, rot } => {
            w.place_item(p, &kind, tx, ty, rot).err().and_then(err)
        }
        ClientMsg::RemoveItem { id } => w.remove_item(p, id).err().and_then(err),
        ClientMsg::LinkPortal { id, target_room } => {
            w.link_portal(p, id, target_room).err().and_then(err)
        }
        ClientMsg::EnterPortal { id } => w.enter_portal(p, id).err().and_then(err),
        ClientMsg::GoHome => w.go_home(p).err().and_then(err),
        ClientMsg::Chat { text } => {
            w.chat(p, &text);
            None
        }
        ClientMsg::ListRooms => match w.list_rooms() {
            Ok(rooms) => Some(ServerMsg::Rooms { rooms }),
            Err(e) => {
                warn!("list_rooms: {e}");
                err(e)
            }
        },
        ClientMsg::Talk { npc_id, choice } => npc::talk(&mut w, p, npc_id, choice),
        ClientMsg::Ping => Some(ServerMsg::Pong),
    }
}
