//! JSON message envelopes shared by the server, the CLI and (by convention) Godot.
use serde::{Deserialize, Serialize};

pub const DEFAULT_PORT: u16 = 8787;
pub const GRID_W: i32 = 14;
pub const GRID_H: i32 = 14;
/// Tiles 0..8 x 0..8 are the house floor; the rest is garden. The pond is not buildable.
pub const POND_CENTRE: (i32, i32) = (11, 10);
pub const POND_RADIUS: f32 = 2.1;

pub fn tile_blocked(tx: i32, ty: i32) -> bool {
    let dx = (tx as f32 + 0.5) - (POND_CENTRE.0 as f32 + 0.5);
    let dy = (ty as f32 + 0.5) - (POND_CENTRE.1 as f32 + 0.5);
    (dx * dx + dy * dy).sqrt() < POND_RADIUS
}

pub const ITEM_KINDS: &[&str] = &[
    "palm",
    "monstera",
    "flower_pot",
    "cactus",
    "bed",
    "table",
    "chair",
    "lamp",
    "rug",
    "bookshelf",
    "portal",
    "tree",
    "bench",
    "flower_bed",
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Player {
    pub id: i64,
    pub name: String,
    pub colour: String,
    pub home_room: i64,
    pub x: f32,
    pub y: f32,
    /// Server-driven islander (negative id). Clients may style them differently.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub is_npc: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Item {
    pub id: i64,
    pub room_id: i64,
    pub kind: String,
    pub tx: i32,
    pub ty: i32,
    pub rot: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_room: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RoomState {
    pub id: i64,
    pub name: String,
    pub owner_id: i64,
    pub owner_name: String,
    pub width: i32,
    pub height: i32,
    pub items: Vec<Item>,
    pub players: Vec<Player>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RoomSummary {
    pub id: i64,
    pub name: String,
    pub owner: String,
    pub visitors: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMsg {
    Hello {
        name: String,
        #[serde(default)]
        colour: Option<String>,
    },
    Move {
        x: f32,
        y: f32,
    },
    PlaceItem {
        kind: String,
        tx: i32,
        ty: i32,
        #[serde(default)]
        rot: i32,
    },
    RemoveItem {
        id: i64,
    },
    LinkPortal {
        id: i64,
        target_room: i64,
    },
    EnterPortal {
        id: i64,
    },
    GoHome,
    Chat {
        text: String,
    },
    ListRooms,
    /// Start (choice = None) or continue (choice = Some(index)) a dialogue with an NPC.
    Talk {
        npc_id: i64,
        #[serde(default)]
        choice: Option<usize>,
    },
    Ping,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMsg {
    Welcome {
        player_id: i64,
        room: RoomState,
    },
    RoomState {
        room: RoomState,
    },
    PlayerJoined {
        player: Player,
    },
    PlayerLeft {
        player_id: i64,
    },
    PlayerMoved {
        player_id: i64,
        x: f32,
        y: f32,
    },
    ItemPlaced {
        item: Item,
    },
    ItemRemoved {
        id: i64,
    },
    PortalLinked {
        id: i64,
        target_room: i64,
    },
    Chat {
        player_id: i64,
        name: String,
        text: String,
    },
    Rooms {
        rooms: Vec<RoomSummary>,
    },
    /// NPC dialogue step for one player: what the NPC says + the replies the player may pick.
    Dialogue {
        npc_id: i64,
        name: String,
        text: String,
        options: Vec<String>,
    },
    Pong,
    Error {
        message: String,
    },
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn roundtrip() {
        let m = ClientMsg::PlaceItem {
            kind: "palm".into(),
            tx: 1,
            ty: 2,
            rot: 0,
        };
        let s = serde_json::to_string(&m).unwrap();
        assert_eq!(
            s,
            r#"{"type":"place_item","kind":"palm","tx":1,"ty":2,"rot":0}"#
        );
        assert_eq!(serde_json::from_str::<ClientMsg>(&s).unwrap(), m);
    }
}
