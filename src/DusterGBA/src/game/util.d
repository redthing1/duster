module game.util;

import ldc.attributes;

import tonc;
import game;

extern (C):

bool board_util_is_on_board(int tx, int ty) {
    return ((tx >= 0) && tx < game_state.board_size)
        && ((ty >= 0) && ty < game_state.board_size);
}

bool board_util_is_walkable(int tx, int ty) {
    if (!board_util_is_on_board(tx, ty))
        return false;

    // check terrain
    Terrain terrain = board_get_terrain(BOARD_POS(tx, ty));
    if (terrain == Terrain.TERRAIN_GROUND)
        return true;

    return false;
}

tile_neighbors_t board_util_get_neighbors(int tile_id) {
    tile_neighbors_t ret;

    VPos16 tile_pos = board_util_tid_to_pos(tile_id);

    // fill the neighbors
    // north, east, south, west
    // if not valid, then -1

    ret.neighbors[0] = -1;
    ret.neighbors[1] = -1;
    ret.neighbors[2] = -1;
    ret.neighbors[3] = -1;

    // north
    if (board_util_is_on_board(tile_pos.x, tile_pos.y - 1)) {
        ret.neighbors[0] = BOARD_POS(tile_pos.x, tile_pos.y - 1);
    }
    // east
    if (board_util_is_on_board(tile_pos.x + 1, tile_pos.y)) {
        ret.neighbors[1] = BOARD_POS(tile_pos.x + 1, tile_pos.y);
    }
    // south
    if (board_util_is_on_board(tile_pos.x, tile_pos.y + 1)) {
        ret.neighbors[2] = BOARD_POS(tile_pos.x, tile_pos.y + 1);
    }
    // west
    if (board_util_is_on_board(tile_pos.x - 1, tile_pos.y)) {
        ret.neighbors[3] = BOARD_POS(tile_pos.x - 1, tile_pos.y);
    }

    return ret;
}

// check whether a tile id is a neighbor
bool board_util_is_neighbor(int tile_id, int neighbor_id) {
    tile_neighbors_t neighbors = board_util_get_neighbors(tile_id);
    return neighbors.neighbors[0] == neighbor_id || neighbors.neighbors[1] == neighbor_id || neighbors
        .neighbors[2] == neighbor_id || neighbors.neighbors[3] == neighbor_id;
}

// get tile board position from tid
VPos16 board_util_tid_to_pos(int tile_id) {
    // return (VPos16) {tile_id % MAX_BOARD_SIZE, tile_id / MAX_BOARD_SIZE};
    return VPos16(cast(s16)(tile_id % game_state.board_size), cast(s16)(
            tile_id / game_state.board_size));
}

// get tid from board position
int board_util_pos_to_tid(VPos16 pos) {
    return BOARD_POS(pos.x, pos.y);
}

// typedef struct {
//     int tile_id;
// } BFSVisitStorage;

// typedef struct {
//     int dist;
//     int ix;
//     int value;
// } DijkstraStorage;

// typedef struct {
//     int value;
//     int prio;
//     int ix;
// } PQueuePair;

struct BFSVisitStorage {
    int tile_id;
};

struct DijkstraStorage {
    int dist;
    int ix;
    int value;
};

struct PQueuePair {
    int value;
    int prio;
    int ix;
};

static int pqueue_pair_cmp(const void* a, const void* b) {
    PQueuePair* a1 = cast(PQueuePair*) a;
    PQueuePair* b1 = cast(PQueuePair*) b;

    return b1.prio - a1.prio;
}

int board_util_calc_rangebuf(int start_tx, int start_ty, int range, VPos16* pos_buf, int pos_buf_len) {
    return 0;
}

bool pawn_util_is_valid_move(pawn_gid_t pawn_gid, VPos16 start_pos, VPos16 end_pos) {
    ClassData* class_data = pawn_get_classdata(pawn_gid);

    int pawn_max_move = class_data.move;

    // check dist from start to end tiles
    int start_end_dist = board_dist(start_pos.x, start_pos.y, end_pos.x, end_pos.y);

    // check if dist exceeds max move
    if (start_end_dist > pawn_max_move)
        return false;

    return true;
}

bool pawn_util_is_valid_interaction(pawn_gid_t pawn1_gid, VPos16 pawn1_pos, pawn_gid_t pawn2_gid, VPos16 pawn2_pos) {
    // ClassData* class_data = pawn_get_classdata(pawn_gid);

    // int pawn_max_move = class_data.move;

    // // check dist from start to end tiles
    // int start_end_dist = board_dist(start_pos.x, start_pos.y, end_pos.x, end_pos.y);

    // // check if dist exceeds max move
    // if (start_end_dist > pawn_max_move)
    //     return false;

    return true;
}

bool pawn_util_on_same_team(pawn_gid_t pawn1, pawn_gid_t pawn2) {
    return PAWN_WHICH_TEAM(pawn1) == PAWN_WHICH_TEAM(pawn2);
}

bool game_util_is_my_turn(pawn_gid_t pawn_gid) {
    int my_team = PAWN_WHICH_TEAM(pawn_gid);
    int whose_turn = game_util_whose_turn();

    return my_team == whose_turn;
}

int game_util_whose_turn() {
    int whose_turn = game_state.turns % NUM_TEAMS;
    return whose_turn;
}

bool pawn_util_moved_this_turn(Pawn* pawn) {
    if (pawn.last_moved_turn >= game_state.turns)
        return true;
    return false;
}

// this applies the growth spread out over every 5 levels
// for example, with an atk growth of 4, it will spread those
// 4 atk stat boosts over every 5 levels
// auto MACRO_CALC_STATS_GROWTH(stat) calc_stats.stat = base.stat + ((growth.stat * num_growths) / 5)

UnitDataStats pawn_util_calc_stats(ClassData* class_data, int level) {
    int num_growths = (level - 1);
    UnitDataStats base = class_data.base_stats;
    UnitDataStats growth = class_data.stat_growths;

    UnitDataStats calc_stats = base;

    // compute additional stats based on adding to base stats
    // calc_stats.atk = base.atk + (num_growths * growth.atk);
    // calc_stats.def = base.def + (num_growths * growth.def);
    // calc_stats.hp = base.hp + (num_growths * growth.hp);

    // use a macro to spread out the growth over every 5 levels

    // TODO: reimplement this in D

    // MACRO_CALC_STATS_GROWTH(atk);
    // MACRO_CALC_STATS_GROWTH(def);
    // MACRO_CALC_STATS_GROWTH(hp);
    // MACRO_CALC_STATS_GROWTH(spd);

    return calc_stats;
}

int game_util_randint() {
    // each random call is only up to 32768
    int r1 = qran();
    int r2 = qran();
    int r3 = qran();
    int r4 = qran();
    // we want to combine them to a single number, using masked 8 bits from each
    int r = (r1 & 0xFF) | ((r2 & 0xFF) << 8) | ((r3 & 0xFF) << 16) | ((r4 & 0xFF) << 24);
    return r;
}
