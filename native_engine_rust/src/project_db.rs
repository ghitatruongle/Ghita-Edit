//! T5-P1: SQLite project format + media library database.
//!
//! Provides persistent storage for projects (replacing JSON `.ghita` files)
//! and a searchable media library with tags, ratings, and metadata.
//! Feature-gated behind `sqlite`.

#[cfg(feature = "sqlite")]
use rusqlite::{params, Connection, Result};
#[cfg(feature = "sqlite")]
use std::path::Path;

/// Project information returned by list operations.
#[cfg(feature = "sqlite")]
#[derive(Debug, Clone)]
pub struct ProjectInfo {
    pub id: i64,
    pub name: String,
    pub version: String,
    pub created_at: String,
    pub modified_at: String,
}

/// Media library entry.
#[cfg(feature = "sqlite")]
#[derive(Debug, Clone)]
pub struct MediaEntry {
    pub id: i64,
    pub path: String,
    pub hash: String,
    pub tags: String,
    pub rating: i32,
    pub metadata_json: String,
    pub last_seen: String,
}

/// SQLite-backed project and media library database.
#[cfg(feature = "sqlite")]
pub struct ProjectDb {
    conn: Connection,
}

#[cfg(feature = "sqlite")]
impl ProjectDb {
    /// Open or create a `.ghita.db` SQLite database at the given path.
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS projects (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                version TEXT NOT NULL DEFAULT '1.5.0',
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                modified_at TEXT NOT NULL DEFAULT (datetime('now')),
                json_data TEXT NOT NULL DEFAULT '{}'
            );
            CREATE TABLE IF NOT EXISTS media_library (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL UNIQUE,
                hash TEXT NOT NULL DEFAULT '',
                tags TEXT NOT NULL DEFAULT '',
                rating INTEGER NOT NULL DEFAULT 0,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                thumbnail_blob BLOB,
                last_seen TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_media_tags ON media_library(tags);
            CREATE INDEX IF NOT EXISTS idx_media_rating ON media_library(rating);
            CREATE INDEX IF NOT EXISTS idx_media_hash ON media_library(hash);",
        )?;
        Ok(Self { conn })
    }

    /// Save a project (insert or update by name).
    pub fn save_project(&self, name: &str, json_data: &str) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO projects (name, json_data, modified_at)
             VALUES (?1, ?2, datetime('now'))
             ON CONFLICT(name) DO UPDATE SET
                json_data = excluded.json_data,
                modified_at = datetime('now')",
            params![name, json_data],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Load a project's JSON data by name.
    pub fn load_project(&self, name: &str) -> Result<Option<String>> {
        let mut stmt = self
            .conn
            .prepare("SELECT json_data FROM projects WHERE name = ?1")?;
        let mut rows = stmt.query(params![name])?;
        if let Some(row) = rows.next()? {
            Ok(Some(row.get(0)?))
        } else {
            Ok(None)
        }
    }

    /// List all projects (metadata only, no JSON).
    pub fn list_projects(&self) -> Result<Vec<ProjectInfo>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, name, version, created_at, modified_at FROM projects ORDER BY modified_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(ProjectInfo {
                id: row.get(0)?,
                name: row.get(1)?,
                version: row.get(2)?,
                created_at: row.get(3)?,
                modified_at: row.get(4)?,
            })
        })?;
        rows.collect()
    }

    /// Delete a project by name.
    pub fn delete_project(&self, name: &str) -> Result<bool> {
        let count = self
            .conn
            .execute("DELETE FROM projects WHERE name = ?1", params![name])?;
        Ok(count > 0)
    }

    /// Add or update a media entry in the library.
    pub fn add_media(
        &self,
        path: &str,
        hash: &str,
        metadata_json: &str,
    ) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO media_library (path, hash, metadata_json, last_seen)
             VALUES (?1, ?2, ?3, datetime('now'))
             ON CONFLICT(path) DO UPDATE SET
                hash = excluded.hash,
                metadata_json = excluded.metadata_json,
                last_seen = datetime('now')",
            params![path, hash, metadata_json],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Search media by text query (matches path, tags) and optional rating filter.
    pub fn search_media(&self, query: &str, min_rating: i32) -> Result<Vec<MediaEntry>> {
        let pattern = format!("%{}%", query);
        let mut stmt = self.conn.prepare(
            "SELECT id, path, hash, tags, rating, metadata_json, last_seen
             FROM media_library
             WHERE (path LIKE ?1 OR tags LIKE ?1) AND rating >= ?2
             ORDER BY last_seen DESC",
        )?;
        let rows = stmt.query_map(params![pattern, min_rating], |row| {
            Ok(MediaEntry {
                id: row.get(0)?,
                path: row.get(1)?,
                hash: row.get(2)?,
                tags: row.get(3)?,
                rating: row.get(4)?,
                metadata_json: row.get(5)?,
                last_seen: row.get(6)?,
            })
        })?;
        rows.collect()
    }

    /// Update rating for a media entry by ID.
    pub fn update_rating(&self, id: i64, rating: i32) -> Result<bool> {
        let count = self.conn.execute(
            "UPDATE media_library SET rating = ?1 WHERE id = ?2",
            params![rating, id],
        )?;
        Ok(count > 0)
    }

    /// Update tags for a media entry by ID.
    pub fn update_tags(&self, id: i64, tags: &str) -> Result<bool> {
        let count = self.conn.execute(
            "UPDATE media_library SET tags = ?1 WHERE id = ?2",
            params![tags, id],
        )?;
        Ok(count > 0)
    }

    /// Import a project from a JSON string (migration from .ghita files).
    pub fn import_from_json(&self, name: &str, json_data: &str) -> Result<i64> {
        self.save_project(name, json_data)
    }

    /// Export a project to JSON string (backward compat with .ghita files).
    pub fn export_to_json(&self, name: &str) -> Result<Option<String>> {
        self.load_project(name)
    }

    /// Get total count of media entries.
    pub fn media_count(&self) -> Result<i64> {
        let mut stmt = self.conn.prepare("SELECT COUNT(*) FROM media_library")?;
        let count: i64 = stmt.query_row([], |row| row.get(0))?;
        Ok(count)
    }

    /// Get total count of projects.
    pub fn project_count(&self) -> Result<i64> {
        let mut stmt = self.conn.prepare("SELECT COUNT(*) FROM projects")?;
        let count: i64 = stmt.query_row([], |row| row.get(0))?;
        Ok(count)
    }
}

#[cfg(all(test, feature = "sqlite"))]
mod tests {
    use super::*;
    use std::fs;

    fn temp_db() -> (ProjectDb, String) {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let path = format!(
            "target/test_t5_{}_{}.db",
            std::process::id(),
            id
        );
        let _ = fs::remove_file(&path);
        let db = ProjectDb::open(&path).expect("open db");
        (db, path)
    }

    #[test]
    fn project_round_trip() {
        let (db, path) = temp_db();
        let json = r#"{"name":"test","tracks":[],"version":"1.5.0"}"#;
        db.save_project("test_project", json).unwrap();
        let loaded = db.load_project("test_project").unwrap().unwrap();
        assert_eq!(loaded, json);
        assert_eq!(db.project_count().unwrap(), 1);
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn project_list_and_delete() {
        let (db, path) = temp_db();
        db.save_project("proj_a", "{}").unwrap();
        db.save_project("proj_b", "{}").unwrap();
        let list = db.list_projects().unwrap();
        assert_eq!(list.len(), 2);
        assert!(db.delete_project("proj_a").unwrap());
        assert_eq!(db.project_count().unwrap(), 1);
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn media_library_crud() {
        let (db, path) = temp_db();
        db.add_media("/videos/clip1.mp4", "abc123", "{}").unwrap();
        db.add_media("/videos/clip2.mp4", "def456", "{}").unwrap();
        assert_eq!(db.media_count().unwrap(), 2);

        // Search
        let results = db.search_media("clip1", 0).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].path, "/videos/clip1.mp4");

        // Rating
        db.update_rating(results[0].id, 5).unwrap();
        let rated = db.search_media("", 5).unwrap();
        assert_eq!(rated.len(), 1);

        // Tags
        db.update_tags(results[0].id, "vacation,summer").unwrap();
        let tagged = db.search_media("vacation", 0).unwrap();
        assert_eq!(tagged.len(), 1);

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn migration_from_json() {
        let (db, path) = temp_db();
        let json = r#"{"name":"old_project","tracks":[{"id":1}]}"#;
        db.import_from_json("old_project", json).unwrap();
        let exported = db.export_to_json("old_project").unwrap().unwrap();
        assert_eq!(exported, json);
        let _ = fs::remove_file(&path);
    }
}
