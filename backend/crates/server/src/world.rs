//! In-memory presence: who is in which room and where they stand.
use crate::db::Db;
use anyhow::{anyhow, Result};
use protocol::*;
use serde_json::json;
use std::collections::HashMap;
use std::io::Write;
use tokio::sync::mpsc;

pub type Tx = mpsc::UnboundedSender<ServerMsg>;

pub struct Session {
    pub player: Player,
    pub room_id: i64,
    pub tx: Tx,
}

pub struct World {
    pub db: Db,
    pub sessions: HashMap<i64, Session>,
    pub npcs: Vec<crate::npc::Npc>,
    /// Append-only JSONL audit log of every state change (events.jsonl).
    events: Option<std::fs::File>,
}

impl World {
    pub fn new(db: Db, events_path: Option<&std::path::Path>) -> Result<Self> {
        let events = match events_path {
            Some(p) => Some(
                std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(p)?,
            ),
            None => None,
        };
        Ok(Self {
            db,
            sessions: HashMap::new(),
            npcs: Vec::new(),
            events,
        })
    }

    /// Write one JSON line: {"ts":..., "event":..., ...fields}.
    fn log(&mut self, event: &str, mut fields: serde_json::Value) {
        if let Some(f) = self.events.as_mut() {
            if let serde_json::Value::Object(map) = &mut fields {
                map.insert("event".into(), json!(event));
                map.insert("ts".into(), json!(unix_ms()));
            }
            let _ = writeln!(f, "{fields}");
        }
    }

    pub fn broadcast(&self, room_id: i64, msg: &ServerMsg, except: Option<i64>) {
        for (pid, s) in &self.sessions {
            if s.room_id == room_id && Some(*pid) != except {
                let _ = s.tx.send(msg.clone());
            }
        }
    }

    pub fn room_state(&self, room_id: i64) -> Result<RoomState> {
        let (name, owner_id, owner_name) = self
            .db
            .room_meta(room_id)?
            .ok_or_else(|| anyhow!("no such room {room_id}"))?;
        let mut players: Vec<Player> = self
            .sessions
            .values()
            .filter(|s| s.room_id == room_id)
            .map(|s| s.player.clone())
            .collect();
        players.extend(
            self.npcs
                .iter()
                .filter(|n| n.room_id == room_id)
                .map(|n| n.player.clone()),
        );
        Ok(RoomState {
            id: room_id,
            name,
            owner_id,
            owner_name,
            width: GRID_W,
            height: GRID_H,
            items: self.db.items(room_id)?,
            players,
        })
    }

    pub fn join(&mut self, name: &str, colour: &str, tx: Tx) -> Result<(i64, RoomState)> {
        let mut player = self.db.login(name, colour)?;
        // Kick a stale session with the same name (reconnect).
        if let Some(old) = self.sessions.remove(&player.id) {
            self.broadcast(
                old.room_id,
                &ServerMsg::PlayerLeft {
                    player_id: player.id,
                },
                None,
            );
        }
        let room_id = player.home_room;
        player.x = GRID_W as f32 / 2.0;
        player.y = GRID_H as f32 / 2.0;
        let pid = player.id;
        self.sessions.insert(
            pid,
            Session {
                player: player.clone(),
                room_id,
                tx,
            },
        );
        self.broadcast(room_id, &ServerMsg::PlayerJoined { player }, Some(pid));
        self.log(
            "join",
            json!({"player_id": pid, "name": name, "room": room_id}),
        );
        self.npc_greet(room_id);
        Ok((pid, self.room_state(room_id)?))
    }

    pub fn leave(&mut self, pid: i64) {
        if let Some(s) = self.sessions.remove(&pid) {
            self.broadcast(s.room_id, &ServerMsg::PlayerLeft { player_id: pid }, None);
            self.log("leave", json!({"player_id": pid, "room": s.room_id}));
        }
    }

    pub fn move_to(&mut self, pid: i64, x: f32, y: f32) {
        if !x.is_finite() || !y.is_finite() {
            return;
        }
        let Some(s) = self.sessions.get_mut(&pid) else {
            return;
        };
        let (dx, dy) = (x - 7.0, y - 7.0);
        let scale = (12.0 / dx.hypot(dy).max(12.0)).min(1.0);
        s.player.x = 7.0 + dx * scale;
        s.player.y = 7.0 + dy * scale;
        let (room, x, y) = (s.room_id, s.player.x, s.player.y);
        self.broadcast(
            room,
            &ServerMsg::PlayerMoved {
                player_id: pid,
                x,
                y,
            },
            Some(pid),
        );
    }

    fn require_owner(&self, pid: i64, room_id: i64) -> Result<()> {
        let (_, owner_id, _) = self
            .db
            .room_meta(room_id)?
            .ok_or_else(|| anyhow!("no such room"))?;
        if owner_id != pid {
            return Err(anyhow!("only the island owner can decorate here"));
        }
        Ok(())
    }

    pub fn place_item(&mut self, pid: i64, kind: &str, tx: i32, ty: i32, rot: i32) -> Result<()> {
        let room_id = self
            .sessions
            .get(&pid)
            .ok_or_else(|| anyhow!("not logged in"))?
            .room_id;
        self.require_owner(pid, room_id)?;
        if !ITEM_KINDS.contains(&kind) {
            return Err(anyhow!("unknown item kind '{kind}'"));
        }
        if !(0..GRID_W).contains(&tx) || !(0..GRID_H).contains(&ty) {
            return Err(anyhow!("tile out of range"));
        }
        if tile_blocked(tx, ty) {
            return Err(anyhow!("can't build in the pond"));
        }
        if self
            .db
            .items(room_id)?
            .iter()
            .any(|i| i.tx == tx && i.ty == ty)
        {
            return Err(anyhow!("tile already occupied"));
        }
        let item = self
            .db
            .place_item(room_id, kind, tx, ty, rot.rem_euclid(4))?;
        self.log(
            "place_item",
            json!({"player_id": pid, "room": room_id, "item": item}),
        );
        self.broadcast(room_id, &ServerMsg::ItemPlaced { item }, None);
        Ok(())
    }

    pub fn remove_item(&mut self, pid: i64, id: i64) -> Result<()> {
        let room_id = self
            .sessions
            .get(&pid)
            .ok_or_else(|| anyhow!("not logged in"))?
            .room_id;
        self.require_owner(pid, room_id)?;
        let item = self.db.item(id)?.ok_or_else(|| anyhow!("no such item"))?;
        if item.room_id != room_id {
            return Err(anyhow!("item is not in this room"));
        }
        self.db.remove_item(id)?;
        self.log(
            "remove_item",
            json!({"player_id": pid, "room": room_id, "id": id, "kind": item.kind}),
        );
        self.broadcast(room_id, &ServerMsg::ItemRemoved { id }, None);
        Ok(())
    }

    pub fn link_portal(&mut self, pid: i64, id: i64, target_room: i64) -> Result<()> {
        let room_id = self
            .sessions
            .get(&pid)
            .ok_or_else(|| anyhow!("not logged in"))?
            .room_id;
        self.require_owner(pid, room_id)?;
        let item = self.db.item(id)?.ok_or_else(|| anyhow!("no such item"))?;
        if item.room_id != room_id || item.kind != "portal" {
            return Err(anyhow!("that is not a portal in this room"));
        }
        if !self.db.room_exists(target_room)? {
            return Err(anyhow!("target room does not exist"));
        }
        self.db.link_portal(id, target_room)?;
        self.log(
            "link_portal",
            json!({"player_id": pid, "room": room_id, "id": id, "target_room": target_room}),
        );
        self.broadcast(room_id, &ServerMsg::PortalLinked { id, target_room }, None);
        Ok(())
    }

    pub fn switch_room(&mut self, pid: i64, target: i64) -> Result<()> {
        if !self.db.room_exists(target)? {
            return Err(anyhow!("target room does not exist"));
        }
        let s = self
            .sessions
            .get_mut(&pid)
            .ok_or_else(|| anyhow!("not logged in"))?;
        let old = s.room_id;
        s.room_id = target;
        s.player.x = GRID_W as f32 / 2.0;
        s.player.y = GRID_H as f32 / 2.0;
        let player = s.player.clone();
        let tx = s.tx.clone();
        self.broadcast(old, &ServerMsg::PlayerLeft { player_id: pid }, None);
        self.broadcast(target, &ServerMsg::PlayerJoined { player }, Some(pid));
        self.log(
            "switch_room",
            json!({"player_id": pid, "from": old, "to": target}),
        );
        let _ = tx.send(ServerMsg::RoomState {
            room: self.room_state(target)?,
        });
        self.npc_greet(target);
        Ok(())
    }

    pub fn enter_portal(&mut self, pid: i64, id: i64) -> Result<()> {
        let room_id = self
            .sessions
            .get(&pid)
            .ok_or_else(|| anyhow!("not logged in"))?
            .room_id;
        let item = self.db.item(id)?.ok_or_else(|| anyhow!("no such item"))?;
        if item.room_id != room_id || item.kind != "portal" {
            return Err(anyhow!("that is not a portal in this room"));
        }
        let target = item
            .target_room
            .ok_or_else(|| anyhow!("portal is not linked yet"))?;
        self.switch_room(pid, target)
    }

    pub fn go_home(&mut self, pid: i64) -> Result<()> {
        let home = self
            .sessions
            .get(&pid)
            .ok_or_else(|| anyhow!("not logged in"))?
            .player
            .home_room;
        self.switch_room(pid, home)
    }

    pub fn chat(&mut self, pid: i64, text: &str) {
        let Some(s) = self.sessions.get(&pid) else {
            return;
        };
        let text: String = text.chars().take(240).collect();
        let room = s.room_id;
        let msg = ServerMsg::Chat {
            player_id: pid,
            name: s.player.name.clone(),
            text: text.clone(),
        };
        self.broadcast(room, &msg, None);
        if std::env::var("COAST_LOG_CHAT").as_deref() == Ok("1") {
            self.log(
                "chat",
                json!({"player_id": pid, "room": room, "text": text}),
            );
        }
    }

    fn npc_greet(&mut self, room_id: i64) {
        for n in self.npcs.iter_mut().filter(|n| n.room_id == room_id) {
            n.queue_greeting();
        }
    }

    pub fn list_rooms(&self) -> Result<Vec<RoomSummary>> {
        Ok(self
            .db
            .all_rooms()?
            .into_iter()
            .map(|(id, name, owner)| RoomSummary {
                id,
                name,
                owner,
                visitors: self.sessions.values().filter(|s| s.room_id == id).count(),
            })
            .collect())
    }
}

fn unix_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}
