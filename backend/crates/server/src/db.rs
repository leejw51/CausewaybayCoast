use anyhow::Result;
use protocol::{Item, Player};
use rusqlite::{params, Connection, OptionalExtension};

pub struct Db {
    conn: Connection,
}

impl Db {
    pub fn open(path: &str) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.execute_batch(
            r#"
            PRAGMA journal_mode = WAL;
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS players (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                colour TEXT NOT NULL,
                home_room INTEGER,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE TABLE IF NOT EXISTS rooms (
                id INTEGER PRIMARY KEY,
                owner_id INTEGER NOT NULL REFERENCES players(id),
                name TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY,
                room_id INTEGER NOT NULL REFERENCES rooms(id),
                kind TEXT NOT NULL,
                tx INTEGER NOT NULL,
                ty INTEGER NOT NULL,
                rot INTEGER NOT NULL DEFAULT 0,
                target_room INTEGER REFERENCES rooms(id)
            );
            CREATE INDEX IF NOT EXISTS items_room ON items(room_id);
            "#,
        )?;
        Ok(Self { conn })
    }

    /// Persistent offline demo islands, available without another connected client.
    pub fn seed_demo_friends(&mut self) -> Result<()> {
        let sunny = self.login("Sunny (demo)", "#ffd285")?;
        let marina = self.login("Marina (demo)", "#88cfc7")?;
        for (room, target) in [
            (sunny.home_room, marina.home_room),
            (marina.home_room, sunny.home_room),
        ] {
            self.conn.execute(
                "UPDATE items SET target_room = ?1 WHERE room_id = ?2 AND kind = 'portal' AND target_room IS NULL",
                params![target, room],
            )?;
        }
        Ok(())
    }

    /// Find or create a player, creating their home room the first time.
    pub fn login(&mut self, name: &str, colour: &str) -> Result<Player> {
        let existing: Option<(i64, String, i64)> = self
            .conn
            .query_row(
                "SELECT id, colour, home_room FROM players WHERE name = ?1",
                params![name],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?;
        if let Some((id, col, home)) = existing {
            return Ok(Player {
                id,
                name: name.into(),
                colour: col,
                home_room: home,
                x: 0.0,
                y: 0.0,
                is_npc: false,
            });
        }
        let tx = self.conn.transaction()?;
        tx.execute(
            "INSERT INTO players(name, colour) VALUES (?1, ?2)",
            params![name, colour],
        )?;
        let pid = tx.last_insert_rowid();
        tx.execute(
            "INSERT INTO rooms(owner_id, name) VALUES (?1, ?2)",
            params![pid, format!("{}'s island", name)],
        )?;
        let rid = tx.last_insert_rowid();
        tx.execute(
            "UPDATE players SET home_room = ?1 WHERE id = ?2",
            params![rid, pid],
        )?;
        // A starter set so a fresh island is not empty.
        for (kind, x, y) in [
            ("flower_pot", 7, 0),
            ("rug", 3, 3),
            ("portal", 10, 4),
            ("palm", 12, 12),
            ("tree", 9, 12),
            ("bench", 12, 7),
            ("flower_bed", 9, 8),
        ] {
            tx.execute(
                "INSERT INTO items(room_id, kind, tx, ty, rot) VALUES (?1, ?2, ?3, ?4, 0)",
                params![rid, kind, x, y],
            )?;
        }
        tx.execute(
            "UPDATE items SET target_room = (SELECT home_room FROM players WHERE name = 'Sunny (demo)' AND id != ?1) WHERE room_id = ?2 AND kind = 'portal'",
            params![pid, rid],
        )?;
        tx.commit()?;
        Ok(Player {
            id: pid,
            name: name.into(),
            colour: colour.into(),
            home_room: rid,
            x: 0.0,
            y: 0.0,
            is_npc: false,
        })
    }

    pub fn room_meta(&self, room_id: i64) -> Result<Option<(String, i64, String)>> {
        Ok(self
            .conn
            .query_row(
                "SELECT r.name, r.owner_id, p.name FROM rooms r JOIN players p ON p.id = r.owner_id WHERE r.id = ?1",
                params![room_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?)
    }

    pub fn items(&self, room_id: i64) -> Result<Vec<Item>> {
        let mut st = self.conn.prepare(
            "SELECT id, room_id, kind, tx, ty, rot, target_room FROM items WHERE room_id = ?1 ORDER BY id",
        )?;
        let rows = st.query_map(params![room_id], |r| {
            Ok(Item {
                id: r.get(0)?,
                room_id: r.get(1)?,
                kind: r.get(2)?,
                tx: r.get(3)?,
                ty: r.get(4)?,
                rot: r.get(5)?,
                target_room: r.get(6)?,
            })
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    pub fn item(&self, id: i64) -> Result<Option<Item>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, room_id, kind, tx, ty, rot, target_room FROM items WHERE id = ?1",
                params![id],
                |r| {
                    Ok(Item {
                        id: r.get(0)?,
                        room_id: r.get(1)?,
                        kind: r.get(2)?,
                        tx: r.get(3)?,
                        ty: r.get(4)?,
                        rot: r.get(5)?,
                        target_room: r.get(6)?,
                    })
                },
            )
            .optional()?)
    }

    pub fn place_item(&self, room_id: i64, kind: &str, tx: i32, ty: i32, rot: i32) -> Result<Item> {
        self.conn.execute(
            "INSERT INTO items(room_id, kind, tx, ty, rot) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![room_id, kind, tx, ty, rot],
        )?;
        let id = self.conn.last_insert_rowid();
        Ok(Item {
            id,
            room_id,
            kind: kind.into(),
            tx,
            ty,
            rot,
            target_room: None,
        })
    }

    pub fn remove_item(&self, id: i64) -> Result<bool> {
        Ok(self
            .conn
            .execute("DELETE FROM items WHERE id = ?1", params![id])?
            > 0)
    }

    pub fn link_portal(&self, id: i64, target_room: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE items SET target_room = ?1 WHERE id = ?2",
            params![target_room, id],
        )?;
        Ok(())
    }

    pub fn room_exists(&self, id: i64) -> Result<bool> {
        Ok(self
            .conn
            .query_row("SELECT 1 FROM rooms WHERE id = ?1", params![id], |_| Ok(()))
            .optional()?
            .is_some())
    }

    pub fn all_rooms(&self) -> Result<Vec<(i64, String, String)>> {
        let mut st = self
            .conn
            .prepare("SELECT r.id, r.name, p.name FROM rooms r JOIN players p ON p.id = r.owner_id ORDER BY r.id")?;
        let rows = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?;
        Ok(rows.collect::<Result<_, _>>()?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn demo_friends_are_repeatable_and_new_players_can_visit() {
        let mut db = Db::open(":memory:").unwrap();
        db.seed_demo_friends().unwrap();
        db.seed_demo_friends().unwrap();
        assert_eq!(db.all_rooms().unwrap().len(), 2);
        let player = db.login("visitor", "#ffffff").unwrap();
        let items = db.items(player.home_room).unwrap();
        let portal = items.iter().find(|item| item.kind == "portal").unwrap();
        let target = portal.target_room.unwrap();
        assert_ne!(target, player.home_room);
        assert!(db.room_meta(target).unwrap().unwrap().0.contains("(demo)"));
        assert!(db
            .items(target)
            .unwrap()
            .iter()
            .any(|item| item.kind == "portal" && item.target_room.is_some()));
    }
}
