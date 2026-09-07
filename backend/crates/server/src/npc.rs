//! Islander NPCs: wander the garden, greet arrivals, chatter, hop between islands, answer pokes.
use crate::world::World;
use protocol::*;
use rand::{seq::IndexedRandom, Rng};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const TICK: f32 = 0.25;
const WALK_SPEED: f32 = 3.0; // must match the client's Avatar.SPEED so arrival times line up

pub struct NpcDef {
    pub name: &'static str,
    pub colour: &'static str,
    pub greet: &'static [&'static str],
    pub idle: &'static [&'static str],
    pub talk: &'static [&'static str],
    /// Dialogue menu: (player reply, what it does)
    pub menu: &'static [(&'static str, Reply)],
}

#[derive(Clone, Copy)]
pub enum Reply {
    Tip,
    Story(&'static str),
    Gift(&'static str),
    WhereIsEveryone,
    Follow,
    Bye,
}

pub const CAST: &[NpcDef] = &[
    NpcDef {
        name: "Momo the gardener",
        colour: "#3fbf5a",
        greet: &["Welcome! Mind the tulips.", "Oh hi! The soil is perfect today."],
        idle: &["These hedges won't trim themselves…", "I think the monstera grew overnight.", "Hmm, more flower beds by the pond?"],
        talk: &["Plant a tree next to the bench, it gives lovely shade.", "Right-click an item in Decorate mode to remove it.", "The duck's name is Pudding. Don't tell anyone."],
        menu: &[("Any gardening tips?", Reply::Tip), ("Could I have a plant?", Reply::Gift("flower_pot")),
                ("Tell me about the pond", Reply::Story("I dug it myself. Pudding moved in the same afternoon and never left.")), ("Bye!", Reply::Bye)],
    },
    NpcDef {
        name: "Kai the fisher",
        colour: "#4d7cff",
        greet: &["Ahoy! Fresh catch, sort of.", "Hey there, sailor."],
        idle: &["The tide's coming in…", "Saw a big one by the pier this morning.", "Boat needs a new coat of red."],
        talk: &["Walk onto a linked portal to visit a friend's island.", "The pier is the best spot for sunsets.", "Press R to rotate what you're placing."],
        menu: &[("Any tips?", Reply::Tip), ("Tell me a fish story", Reply::Story("Once I hooked something so big it pulled the whole boat. Turned out to be the pier.")),
                ("Got a spare palm?", Reply::Gift("palm")), ("Bye!", Reply::Bye)],
    },
    NpcDef {
        name: "Coco the seller",
        colour: "#f2a23a",
        greet: &["Coconuts! Get your coconuts!", "Welcome, welcome, best prices on the coast."],
        idle: &["Two coconuts for the price of two!", "Business is… tropical.", "I should open a stall by the umbrella."],
        talk: &["Open Islands to see who's around, then link your portal.", "A lamp by the bed makes the hut cozy at night.", "Rugs go great in the middle of the floor."],
        menu: &[("Any tips?", Reply::Tip), ("What's for sale?", Reply::Gift("bench")),
                ("How's business?", Reply::Story("Tropical. Slow, sunny, and everyone pays in seashells.")), ("Bye!", Reply::Bye)],
    },
    NpcDef {
        name: "Pip the postie",
        colour: "#ff6fa5",
        greet: &["Mail call! …just kidding, nothing today.", "Hi! Lovely island you've got."],
        idle: &["Which way to island #3 again?", "Portals make my job so much easier.", "Nice hedge. Very rectangular."],
        talk: &["Chat is per island. Friends see your bubbles only when they're here.", "Every island starts with one portal. Link it in Decorate mode.", "I hop between islands. Follow me some time!"],
        menu: &[("Any tips?", Reply::Tip), ("Where is everyone?", Reply::WhereIsEveryone), ("Follow me!", Reply::Follow), ("Bye!", Reply::Bye)],
    },
];

pub struct Npc {
    pub player: Player,
    pub room_id: i64,
    pub def: &'static NpcDef,
    wait: f32,
    chatter: f32,
    hop: f32,
    pending: Option<(f32, String)>,
    follow: Option<(i64, f32)>,
}

impl Npc {
    pub fn new(i: usize, def: &'static NpcDef, room_id: i64) -> Self {
        let mut rng = rand::rng();
        Self {
            player: Player {
                id: -(i as i64 + 1),
                name: def.name.into(),
                colour: def.colour.into(),
                home_room: room_id,
                x: GRID_W as f32 / 2.0 + 2.0,
                y: GRID_H as f32 / 2.0 + 2.0,
                is_npc: true,
            },
            room_id,
            def,
            wait: rng.random_range(1.0..3.0),
            chatter: rng.random_range(12.0..30.0),
            hop: rng.random_range(60.0..150.0),
            pending: None,
            follow: None,
        }
    }

    pub fn queue_greeting(&mut self) {
        let mut rng = rand::rng();
        let line = self.def.greet.choose(&mut rng).unwrap().to_string();
        self.pending = Some((rng.random_range(1.2..2.5), line));
    }
}

fn humans_in(world: &World, room: i64) -> usize {
    world
        .sessions
        .values()
        .filter(|s| s.room_id == room)
        .count()
}

/// A random walkable garden/floor tile centre that is not the pond or an item.
fn pick_target(world: &World, room: i64) -> (f32, f32) {
    let mut rng = rand::rng();
    let items = world.db.items(room).unwrap_or_default();
    for _ in 0..20 {
        let tx = rng.random_range(0..GRID_W);
        let ty = rng.random_range(0..GRID_H);
        if tile_blocked(tx, ty) || items.iter().any(|i| i.tx == tx && i.ty == ty) {
            continue;
        }
        return (tx as f32 + 0.5, ty as f32 + 0.5);
    }
    (GRID_W as f32 / 2.0, GRID_H as f32 / 2.0)
}

/// One simulation step for every NPC. Called with the world locked.
pub fn tick(world: &mut World) {
    let mut rng = rand::rng();
    let rooms: Vec<i64> = world
        .db
        .all_rooms()
        .map(|r| r.into_iter().map(|x| x.0).collect())
        .unwrap_or_default();
    if rooms.is_empty() {
        return;
    }
    // Make sure every island with people on it has at least one islander.
    let occupied: Vec<i64> = rooms
        .iter()
        .copied()
        .filter(|r| humans_in(world, *r) > 0)
        .collect();
    for room in &occupied {
        if world.npcs.iter().any(|n| n.room_id == *room) {
            continue;
        }
        // send an NPC that is currently on an empty island
        if let Some(idx) = world
            .npcs
            .iter()
            .position(|n| humans_in(world, n.room_id) == 0)
        {
            move_npc(world, idx, *room);
        }
    }

    for idx in 0..world.npcs.len() {
        let humans = humans_in(world, world.npcs[idx].room_id);
        let room = world.npcs[idx].room_id;
        // pending greeting
        if let Some((t, line)) = world.npcs[idx].pending.take() {
            let t = t - TICK;
            if t <= 0.0 {
                say(world, idx, line);
            } else {
                world.npcs[idx].pending = Some((t, line));
            }
        }
        if humans == 0 {
            continue; // nobody watching: sleep
        }
        // following a player: keep within ~1.5 tiles of them
        if let Some((pid, t)) = world.npcs[idx].follow {
            let t = t - TICK;
            world.npcs[idx].follow = if t > 0.0 { Some((pid, t)) } else { None };
            if let Some(s) = world.sessions.get(&pid) {
                if s.room_id == room {
                    let (px, py) = (s.player.x, s.player.y);
                    let n = &mut world.npcs[idx];
                    let d = ((n.player.x - px).powi(2) + (n.player.y - py).powi(2)).sqrt();
                    if d > 2.2 && n.wait <= 0.0 {
                        let (x, y) = (
                            px + (n.player.x - px) / d * 1.3,
                            py + (n.player.y - py) / d * 1.3,
                        );
                        n.player.x = x;
                        n.player.y = y;
                        n.wait = (d - 1.3) / WALK_SPEED + 0.3;
                        let id = n.player.id;
                        world.broadcast(
                            room,
                            &ServerMsg::PlayerMoved {
                                player_id: id,
                                x,
                                y,
                            },
                            None,
                        );
                    }
                    world.npcs[idx].wait -= TICK;
                    continue;
                }
            }
            world.npcs[idx].follow = None;
        }
        // wander (sometimes towards a player)
        world.npcs[idx].wait -= TICK;
        if world.npcs[idx].wait <= 0.0 {
            let (x, y) = if rng.random_bool(0.3) {
                let humans: Vec<(f32, f32)> = world
                    .sessions
                    .values()
                    .filter(|s| s.room_id == room)
                    .map(|s| (s.player.x, s.player.y))
                    .collect();
                match humans.choose(&mut rng) {
                    Some((hx, hy)) => beside(world, room, *hx, *hy),
                    None => pick_target(world, room),
                }
            } else {
                pick_target(world, room)
            };
            let n = &mut world.npcs[idx];
            let dist = ((n.player.x - x).powi(2) + (n.player.y - y).powi(2)).sqrt();
            n.player.x = x;
            n.player.y = y;
            n.wait = dist / WALK_SPEED + rng.random_range(2.0..7.0);
            let id = n.player.id;
            world.broadcast(
                room,
                &ServerMsg::PlayerMoved {
                    player_id: id,
                    x,
                    y,
                },
                None,
            );
        }
        // chatter
        world.npcs[idx].chatter -= TICK;
        if world.npcs[idx].chatter <= 0.0 {
            world.npcs[idx].chatter = rng.random_range(20.0..45.0);
            let line = world.npcs[idx]
                .def
                .idle
                .choose(&mut rng)
                .unwrap()
                .to_string();
            say(world, idx, line);
        }
        // occasionally hop to another island (only if this one keeps another islander)
        world.npcs[idx].hop -= TICK;
        if world.npcs[idx].hop <= 0.0 {
            world.npcs[idx].hop = rng.random_range(60.0..150.0);
            let others = world.npcs.iter().filter(|n| n.room_id == room).count();
            if others > 1 {
                if let Some(dest) = rooms
                    .iter()
                    .copied()
                    .filter(|r| *r != room)
                    .collect::<Vec<_>>()
                    .choose(&mut rng)
                {
                    say(world, idx, "Off to the next island, see you!".into());
                    move_npc(world, idx, *dest);
                }
            }
        }
    }
}

fn say(world: &mut World, idx: usize, text: String) {
    let n = &world.npcs[idx];
    let msg = ServerMsg::Chat {
        player_id: n.player.id,
        name: n.player.name.clone(),
        text,
    };
    world.broadcast(n.room_id, &msg, None);
}

fn move_npc(world: &mut World, idx: usize, dest: i64) {
    let old = world.npcs[idx].room_id;
    let id = world.npcs[idx].player.id;
    world.broadcast(old, &ServerMsg::PlayerLeft { player_id: id }, None);
    {
        let n = &mut world.npcs[idx];
        n.room_id = dest;
        n.player.x = GRID_W as f32 / 2.0 + 2.5;
        n.player.y = GRID_H as f32 / 2.0 + 2.5;
        n.wait = 1.0;
    }
    let player = world.npcs[idx].player.clone();
    world.broadcast(dest, &ServerMsg::PlayerJoined { player }, None);
    if humans_in(world, dest) > 0 {
        world.npcs[idx].queue_greeting();
    }
}

/// A free tile centre next to (x, y), preferring the side facing the NPC.
fn beside(world: &World, room: i64, x: f32, y: f32) -> (f32, f32) {
    let items = world.db.items(room).unwrap_or_default();
    let (tx0, ty0) = (x.floor() as i32, y.floor() as i32);
    for (dx, dy) in [
        (2, 0),
        (0, 2),
        (-2, 0),
        (0, -2),
        (2, 2),
        (-2, -2),
        (2, -2),
        (-2, 2),
        (1, 0),
        (0, 1),
        (-1, 0),
        (0, -1),
    ] {
        let (tx, ty) = (tx0 + dx, ty0 + dy);
        if (0..GRID_W).contains(&tx)
            && (0..GRID_H).contains(&ty)
            && !tile_blocked(tx, ty)
            && !items.iter().any(|i| i.tx == tx && i.ty == ty)
        {
            return (tx as f32 + 0.5, ty as f32 + 0.5);
        }
    }
    (x, y)
}

fn dialogue(world: &World, idx: usize, text: String, with_menu: bool) -> ServerMsg {
    let n = &world.npcs[idx];
    ServerMsg::Dialogue {
        npc_id: n.player.id,
        name: n.player.name.clone(),
        text,
        options: if with_menu {
            n.def.menu.iter().map(|(t, _)| t.to_string()).collect()
        } else {
            vec![]
        },
    }
}

/// Dialogue with an NPC. `choice == None` starts it: the NPC walks up to the player and offers
/// its menu. A choice runs the reply and (unless it was "Bye") re-offers the menu.
pub fn talk(world: &mut World, pid: i64, npc_id: i64, choice: Option<usize>) -> Option<ServerMsg> {
    let (room, px, py, pname) = {
        let s = world.sessions.get(&pid)?;
        (s.room_id, s.player.x, s.player.y, s.player.name.clone())
    };
    let idx = world
        .npcs
        .iter()
        .position(|n| n.player.id == npc_id && n.room_id == room)?;
    let mut rng = rand::rng();
    let Some(choice) = choice else {
        // walk up to the player, then greet with the menu
        let (x, y) = beside(world, room, px, py);
        let n = &mut world.npcs[idx];
        let d = ((n.player.x - x).powi(2) + (n.player.y - y).powi(2)).sqrt();
        n.player.x = x;
        n.player.y = y;
        n.wait = 12.0;
        let id = n.player.id;
        world.broadcast(
            room,
            &ServerMsg::PlayerMoved {
                player_id: id,
                x,
                y,
            },
            None,
        );
        let hello = format!(
            "{} Hi {}! What can I do for you?",
            world.npcs[idx].def.greet[0], pname
        );
        let _ = d;
        return Some(dialogue(world, idx, hello, true));
    };
    let (_, reply) = *world.npcs[idx].def.menu.get(choice)?;
    world.npcs[idx].wait = 12.0;
    let text = match reply {
        Reply::Tip => world.npcs[idx]
            .def
            .talk
            .choose(&mut rng)
            .unwrap()
            .to_string(),
        Reply::Story(t) => t.to_string(),
        Reply::Bye => {
            world.npcs[idx].wait = 2.0;
            let line = format!("See you around, {}!", pname);
            say(world, idx, line.clone());
            return Some(dialogue(world, idx, line, false));
        }
        Reply::WhereIsEveryone => {
            let rooms = world.list_rooms().unwrap_or_default();
            let busy: Vec<String> = rooms
                .iter()
                .filter(|r| r.visitors > 0 && r.id != room)
                .map(|r| format!("{} ({} there)", r.name, r.visitors))
                .collect();
            if busy.is_empty() {
                "Quiet day. It's just us on the whole coast right now.".to_string()
            } else {
                format!(
                    "Right now people are at: {}. Link your portal and go say hi!",
                    busy.join(", ")
                )
            }
        }
        Reply::Follow => {
            world.npcs[idx].follow = Some((pid, 60.0));
            world.npcs[idx].wait = 0.0;
            "Lead the way! I'll tag along for a bit.".to_string()
        }
        Reply::Gift(kind) => {
            let owner = world
                .db
                .room_meta(room)
                .ok()
                .flatten()
                .map(|m| m.1 == pid)
                .unwrap_or(false);
            if !owner {
                "I'd love to, but only the island owner can place things here.".to_string()
            } else {
                let (x, y) = beside(world, room, px, py);
                let (tx, ty) = (x.floor() as i32, y.floor() as i32);
                match world.place_item(pid, kind, tx, ty, rng.random_range(0..4)) {
                    Ok(()) => format!(
                        "Here you go, a {} for your island. Take good care of it!",
                        kind.replace('_', " ")
                    ),
                    Err(_) => {
                        "Hmm, there's no free spot next to you. Make some room and ask again."
                            .to_string()
                    }
                }
            }
        }
    };
    say(world, idx, text.clone());
    Some(dialogue(world, idx, text, true))
}

pub fn spawn_all(world: &mut World) {
    let rooms: Vec<i64> = world
        .db
        .all_rooms()
        .map(|r| r.into_iter().map(|x| x.0).collect())
        .unwrap_or_default();
    world.npcs.clear();
    for (i, def) in CAST.iter().enumerate() {
        let room = rooms.get(i % rooms.len().max(1)).copied().unwrap_or(1);
        world.npcs.push(Npc::new(i, def, room));
    }
}

pub fn run(world: Arc<Mutex<World>>) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut iv = tokio::time::interval(Duration::from_secs_f32(TICK));
        loop {
            iv.tick().await;
            let mut w = world.lock().unwrap();
            if w.npcs.is_empty() {
                spawn_all(&mut w);
            }
            tick(&mut w);
        }
    })
}
