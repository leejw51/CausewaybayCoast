//! coastcli — test / verification client for the Causeway Bay Coast backend.
use anyhow::{anyhow, bail, Context, Result};
use clap::{Parser, Subcommand};
use futures_util::{SinkExt, StreamExt};
use protocol::*;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio_tungstenite::{connect_async, tungstenite::Message};

#[derive(Parser)]
#[command(name = "coastcli", about = "Causeway Bay Coast backend test client")]
struct Cli {
    /// WebSocket URL of the server
    #[arg(long, default_value = "ws://127.0.0.1:8787/ws")]
    url: String,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Connect as a player and type raw commands interactively
    Shell {
        #[arg(long, default_value = "cli")]
        name: String,
    },
    /// Run the automated end-to-end scenario against a live server
    Smoke,
    /// Print the known item kinds
    Items,
}

struct Client {
    ws: tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
}

impl Client {
    async fn connect(url: &str) -> Result<Self> {
        let (ws, _) = connect_async(url)
            .await
            .with_context(|| format!("connecting to {url}"))?;
        Ok(Self { ws })
    }
    async fn send(&mut self, m: &ClientMsg) -> Result<()> {
        self.ws
            .send(Message::Text(serde_json::to_string(m)?.into()))
            .await?;
        Ok(())
    }
    async fn recv(&mut self) -> Result<ServerMsg> {
        loop {
            let msg = tokio::time::timeout(Duration::from_secs(3), self.ws.next())
                .await
                .map_err(|_| anyhow!("timed out waiting for server"))?
                .ok_or_else(|| anyhow!("connection closed"))??;
            if let Message::Text(t) = msg {
                return Ok(
                    serde_json::from_str(&t).with_context(|| format!("bad server json: {t}"))?
                );
            }
        }
    }
    /// Receive until a message matching `pred` arrives (skips presence noise).
    async fn wait(&mut self, what: &str, pred: impl Fn(&ServerMsg) -> bool) -> Result<ServerMsg> {
        for _ in 0..20 {
            let m = self.recv().await?;
            if let ServerMsg::Error { message } = &m {
                bail!("server error while waiting for {what}: {message}");
            }
            if pred(&m) {
                return Ok(m);
            }
        }
        bail!("never got {what}")
    }
    async fn expect_error(&mut self, what: &str) -> Result<String> {
        for _ in 0..20 {
            if let ServerMsg::Error { message } = self.recv().await? {
                return Ok(message);
            }
        }
        bail!("expected an error for {what}")
    }
}

fn check(ok: bool, label: &str) -> Result<()> {
    println!("  [{}] {label}", if ok { "PASS" } else { "FAIL" });
    if ok {
        Ok(())
    } else {
        bail!("{label}")
    }
}

async fn smoke(url: &str) -> Result<()> {
    let suffix = std::process::id();
    let alice_name = format!("alice{suffix}");
    let bob_name = format!("bob{suffix}");
    println!("smoke test against {url}");

    // 1. login + starter island
    let mut a = Client::connect(url).await?;
    a.send(&ClientMsg::Hello {
        name: alice_name.clone(),
        colour: Some("#ff8844".into()),
    })
    .await?;
    let ServerMsg::Welcome {
        player_id: aid,
        room: home,
    } = a.recv().await?
    else {
        bail!("no welcome")
    };
    check(home.owner_id == aid, "alice owns her home island")?;
    check(
        home.items.iter().any(|i| i.kind == "portal"),
        "starter island has a portal",
    )?;
    let a_home = home.id;

    // 2. decorate
    a.send(&ClientMsg::PlaceItem {
        kind: "monstera".into(),
        tx: 2,
        ty: 2,
        rot: 1,
    })
    .await?;
    let placed = a
        .wait("item_placed", |m| matches!(m, ServerMsg::ItemPlaced { .. }))
        .await?;
    let ServerMsg::ItemPlaced { item } = placed else {
        unreachable!()
    };
    check(
        item.kind == "monstera" && item.rot == 1,
        "monstera placed with rotation",
    )?;
    a.send(&ClientMsg::PlaceItem {
        kind: "cactus".into(),
        tx: 2,
        ty: 2,
        rot: 0,
    })
    .await?;
    let e = a.expect_error("occupied tile").await?;
    check(
        e.contains("occupied"),
        "placing on an occupied tile is rejected",
    )?;
    a.send(&ClientMsg::PlaceItem {
        kind: "dragon".into(),
        tx: 1,
        ty: 1,
        rot: 0,
    })
    .await?;
    check(
        a.expect_error("unknown kind").await?.contains("unknown"),
        "unknown item kind is rejected",
    )?;
    a.send(&ClientMsg::RemoveItem { id: item.id }).await?;
    a.wait(
        "item_removed",
        |m| matches!(m, ServerMsg::ItemRemoved { id } if *id == item.id),
    )
    .await?;
    check(true, "item removed")?;

    // 3. second player, own island, presence + chat
    let mut b = Client::connect(url).await?;
    b.send(&ClientMsg::Hello {
        name: bob_name.clone(),
        colour: None,
    })
    .await?;
    let ServerMsg::Welcome {
        player_id: bid,
        room: b_home,
    } = b.recv().await?
    else {
        bail!("no welcome")
    };
    check(b_home.id != a_home, "bob gets his own island")?;
    b.send(&ClientMsg::PlaceItem {
        kind: "palm".into(),
        tx: 4,
        ty: 4,
        rot: 0,
    })
    .await?;
    b.wait("item_placed", |m| matches!(m, ServerMsg::ItemPlaced { .. }))
        .await?;

    // 4. portal: alice links her portal to bob's island and walks through
    let portal = home.items.iter().find(|i| i.kind == "portal").unwrap().id;
    a.send(&ClientMsg::EnterPortal { id: portal }).await?;
    check(
        a.expect_error("unlinked portal")
            .await?
            .contains("not linked"),
        "unlinked portal refuses entry",
    )?;
    a.send(&ClientMsg::LinkPortal {
        id: portal,
        target_room: b_home.id,
    })
    .await?;
    a.wait("portal_linked", |m| {
        matches!(m, ServerMsg::PortalLinked { .. })
    })
    .await?;
    a.send(&ClientMsg::EnterPortal { id: portal }).await?;
    let ServerMsg::RoomState { room } = a
        .wait("room_state", |m| matches!(m, ServerMsg::RoomState { .. }))
        .await?
    else {
        unreachable!()
    };
    check(room.id == b_home.id, "alice teleported to bob's island")?;
    check(
        room.items.iter().any(|i| i.kind == "palm"),
        "alice sees bob's palm",
    )?;
    check(
        room.players.iter().any(|p| p.id == bid),
        "alice sees bob standing there",
    )?;
    let ServerMsg::PlayerJoined { player } = b
        .wait("player_joined", |m| {
            matches!(m, ServerMsg::PlayerJoined { .. })
        })
        .await?
    else {
        unreachable!()
    };
    check(player.id == aid, "bob sees alice arrive")?;

    // 5. visitors cannot decorate; movement and chat propagate
    a.send(&ClientMsg::PlaceItem {
        kind: "lamp".into(),
        tx: 1,
        ty: 1,
        rot: 0,
    })
    .await?;
    check(
        a.expect_error("visitor decorate").await?.contains("owner"),
        "visitor cannot decorate",
    )?;
    a.send(&ClientMsg::Move { x: 1.5, y: 6.0 }).await?;
    let ServerMsg::PlayerMoved { player_id, x, .. } = b
        .wait("player_moved", |m| {
            matches!(m, ServerMsg::PlayerMoved { .. })
        })
        .await?
    else {
        unreachable!()
    };
    check(
        player_id == aid && (x - 1.5).abs() < 1e-4,
        "bob sees alice move",
    )?;
    a.send(&ClientMsg::Chat {
        text: "nice palm!".into(),
    })
    .await?;
    let ServerMsg::Chat { text, .. } = b
        .wait("chat", |m| matches!(m, ServerMsg::Chat { .. }))
        .await?
    else {
        unreachable!()
    };
    check(text == "nice palm!", "chat is delivered in room")?;

    // 6. room list and go home
    a.send(&ClientMsg::ListRooms).await?;
    let ServerMsg::Rooms { rooms } = a
        .wait("rooms", |m| matches!(m, ServerMsg::Rooms { .. }))
        .await?
    else {
        unreachable!()
    };
    let bobs = rooms.iter().find(|r| r.id == b_home.id).unwrap();
    check(
        bobs.visitors == 2,
        "room list counts 2 visitors on bob's island",
    )?;
    a.send(&ClientMsg::GoHome).await?;
    let ServerMsg::RoomState { room } = a
        .wait("room_state", |m| matches!(m, ServerMsg::RoomState { .. }))
        .await?
    else {
        unreachable!()
    };
    check(room.id == a_home, "go_home returns alice to her island")?;
    b.wait(
        "player_left",
        |m| matches!(m, ServerMsg::PlayerLeft { player_id } if *player_id == aid),
    )
    .await?;
    check(true, "bob sees alice leave")?;

    // 7. NPCs: an islander lives on every inhabited island and answers when poked
    let npc = match room.players.iter().find(|p| p.is_npc) {
        Some(p) => p.clone(),
        None => {
            let ServerMsg::PlayerJoined { player } = a
                .wait(
                    "npc joins",
                    |m| matches!(m, ServerMsg::PlayerJoined { player } if player.is_npc),
                )
                .await?
            else {
                unreachable!()
            };
            player
        }
    };
    check(npc.id < 0, "an NPC islander is on the island")?;
    a.send(&ClientMsg::Talk {
        npc_id: npc.id,
        choice: None,
    })
    .await?;
    let ServerMsg::Dialogue { options, .. } = a
        .wait("dialogue", |m| matches!(m, ServerMsg::Dialogue { .. }))
        .await?
    else {
        unreachable!()
    };
    check(
        options.len() >= 3,
        "NPC walks up and offers a dialogue menu",
    )?;
    a.send(&ClientMsg::Talk {
        npc_id: npc.id,
        choice: Some(0),
    })
    .await?;
    let ServerMsg::Chat {
        player_id, text, ..
    } = a
        .wait(
            "npc reply",
            |m| matches!(m, ServerMsg::Chat { player_id, .. } if *player_id == npc.id),
        )
        .await?
    else {
        unreachable!()
    };
    check(
        player_id == npc.id && !text.is_empty(),
        "NPC answers the chosen reply in chat",
    )?;

    // 8. persistence: reconnect keeps the same player + portal link
    drop(a);
    let mut a2 = Client::connect(url).await?;
    a2.send(&ClientMsg::Hello {
        name: alice_name,
        colour: None,
    })
    .await?;
    let ServerMsg::Welcome { player_id, room } = a2.recv().await? else {
        bail!("no welcome")
    };
    check(player_id == aid, "reconnect resolves to the same player")?;
    let p = room.items.iter().find(|i| i.id == portal).unwrap();
    check(
        p.target_room == Some(b_home.id),
        "portal link persisted in sqlite",
    )?;

    println!("smoke: all checks passed");
    Ok(())
}

async fn shell(url: &str, name: &str) -> Result<()> {
    let mut c = Client::connect(url).await?;
    c.send(&ClientMsg::Hello {
        name: name.into(),
        colour: None,
    })
    .await?;
    println!("connected as {name}. Type JSON or: move X Y | place KIND TX TY | remove ID | link ID ROOM | enter ID | home | rooms | say TEXT | quit");
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    loop {
        tokio::select! {
            m = c.ws.next() => match m {
                Some(Ok(Message::Text(t))) => println!("<- {t}"),
                Some(Ok(_)) => {}
                _ => { println!("connection closed"); break; }
            },
            line = lines.next_line() => {
                let Some(line) = line? else {
                    // stdin closed (piped usage): give the server a moment to answer, then leave.
                    let deadline = tokio::time::sleep(Duration::from_millis(300));
                    tokio::pin!(deadline);
                    loop {
                        tokio::select! {
                            _ = &mut deadline => break,
                            m = c.ws.next() => match m {
                                Some(Ok(Message::Text(t))) => println!("<- {t}"),
                                Some(Ok(_)) => {}
                                _ => break,
                            },
                        }
                    }
                    break;
                };
                let w: Vec<&str> = line.split_whitespace().collect();
                let msg = match w.as_slice() {
                    [] => continue,
                    ["quit"] => break,
                    ["move", x, y] => ClientMsg::Move { x: x.parse()?, y: y.parse()? },
                    ["place", k, x, y] => ClientMsg::PlaceItem { kind: k.to_string(), tx: x.parse()?, ty: y.parse()?, rot: 0 },
                    ["remove", id] => ClientMsg::RemoveItem { id: id.parse()? },
                    ["link", id, r] => ClientMsg::LinkPortal { id: id.parse()?, target_room: r.parse()? },
                    ["enter", id] => ClientMsg::EnterPortal { id: id.parse()? },
                    ["home"] => ClientMsg::GoHome,
                    ["rooms"] => ClientMsg::ListRooms,
                    ["talk", id] => ClientMsg::Talk { npc_id: id.parse()?, choice: None },
                    ["talk", id, c] => ClientMsg::Talk { npc_id: id.parse()?, choice: Some(c.parse()?) },
                    ["say", ..] => ClientMsg::Chat { text: line[4..].to_string() },
                    _ if line.starts_with('{') => match serde_json::from_str(&line) {
                        Ok(m) => m,
                        Err(e) => { println!("bad json: {e}"); continue; }
                    },
                    _ => { println!("unknown command"); continue; }
                };
                c.send(&msg).await?;
            }
        }
    }
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Shell { name } => shell(&cli.url, &name).await,
        Cmd::Smoke => smoke(&cli.url).await,
        Cmd::Items => {
            for k in ITEM_KINDS {
                println!("{k}");
            }
            Ok(())
        }
    }
}
