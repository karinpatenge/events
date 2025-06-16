-- Extract relationships between movies and genres

CREATE MATERIALIZED VIEW movie_genre AS
SELECT
  m.movie_id AS movie_id,
  g.genre_id AS genre_id,
  DENSE_RANK() OVER (ORDER BY g.genre_id, m.movie_id ) AS movie_genre_id
FROM
  movie m,
  JSON_TABLE (
    m.genre, '$[*]'
    COLUMNS
      genre VARCHAR2 PATH '$'
  ) s,
  genre g
WHERE
  g.name = s.genre;

SELECT * FROM movie_genre;

-- Create SQL Property Graph

CREATE PROPERTY GRAPH IF NOT EXISTS moviestream_graph
VERTEX TABLES (
  movie
    KEY (movie_id)
    LABEL movie
    PROPERTIES ARE ALL COLUMNS,
  genre
    KEY (genre_id)
    LABEL genre
    PROPERTIES ARE ALL COLUMNS
)
edge tables (
  movie_genre
    KEY (movie_genre_id)
    SOURCE key (movie_id) REFERENCES movie (movie_id)
    DESTINATION KEY (genre_id) REFERENCES genre (genre_id)
    LABEL has_genre
    PROPERTIES ARE ALL COLUMNS
);

-- SQL/PGQ queries

SELECT t.*
FROM GRAPH_TABLE (
  moviestream_graph
  MATCH (m IS movie) -[c IS has_genre]-> (g IS genre)
  COLUMNS (m.title AS title, g.name AS genre)
) t
ORDER BY 1;
