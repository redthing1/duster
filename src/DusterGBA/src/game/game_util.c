#include "game.h"
#include <stdio.h>
#include <memory.h>
#include <tonc.h>
#include "cold_data.h"
#include "cc_queue.h"
#include "cc_hashset.h"
#include "contrib/mgba.h"

BOOL board_util_is_on_board(int tx, int ty) {
    return ((tx >= 0) && tx < game_state.board_size) && ((ty >= 0) && ty < game_state.board_size);
}

VPos16 board_util_tile_id_to_pos(int tile_id) {
    VPos16 ret;
    ret.x = tile_id % MAX_BOARD_SIZE;
    ret.y = tile_id / MAX_BOARD_SIZE;
    return ret;
}

typedef struct {
    int neighbors[4];
} tile_neighbors_t;

tile_neighbors_t board_util_get_neighbors(int tile_id) {
    tile_neighbors_t ret;

    VPos16 tile_pos = board_util_tile_id_to_pos(tile_id);

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

typedef struct {
    int tile_id;
    int dist;
} BFSVisitStorage;

int board_util_calc_rangebuf(int start_tx, int start_ty, int range, VPos16* pos_buf, int pos_buf_len) {
    // clear rangebuf
    memset(pos_buf, 0, sizeof(VPos16) * pos_buf_len);
    int pos_buf_ix = 0;

    int start_tid = BOARD_POS(start_tx, start_ty);
    int start_dist = 0;

    // storage for intermediate positions
    const int visit_tile_storage_size = 256;
    BFSVisitStorage visit_tile_storage[visit_tile_storage_size];
    int visit_tile_storage_index = 0;

    // do BFS

    // 0. data structures
    CC_HashSet* visited;
    CC_Deque* queue;
    CC_HashTable* nodedist;

    // set up hashtable to work with int values
    CC_HashSetConf visited_conf;
    cc_hashset_conf_init(&visited_conf);
    visited_conf.hash = GENERAL_HASH;
    visited_conf.key_length = sizeof(int);
    cc_hashset_new_conf(&visited_conf, &visited);

    cc_deque_new(&queue);

    CC_HashTableConf nodedist_conf;
    cc_hashtable_conf_init(&nodedist_conf);
    nodedist_conf.hash = GENERAL_HASH;
    nodedist_conf.key_length = sizeof(int);
    cc_hashtable_new_conf(&nodedist_conf, &nodedist);

    // 1. initial nodes
    cc_deque_add_first(queue, &start_tid);
    cc_hashset_add(visited, &start_tid);
    cc_hashtable_add(nodedist, &start_tid, &start_dist);

    // 2. iterate
    while (cc_deque_size(queue) > 0) {
        int* curr_node_out;
        cc_deque_remove_first(queue, (void*)&curr_node_out);
        int curr_node = *curr_node_out;

        int* curr_node_dist_out;
        cc_hashtable_get(nodedist, curr_node_out, (void*)&curr_node_dist_out);
        int curr_node_dist = *curr_node_dist_out;

        // mgba_printf(MGBA_LOG_ERROR, "bfs deque get: %d", curr_node);

        // add all unvisited neighbors
        // get neighbors
        tile_neighbors_t tn = board_util_get_neighbors(curr_node);
        // check them
        for (int i = 0; i < 4; i++) {
            int scan_node = tn.neighbors[i];

            if (scan_node < 0)
                continue; // invalid

            // calculate scan node values
            int scan_node_dist = curr_node_dist + 1;
            VPos16 scan_node_pos = board_util_tile_id_to_pos(scan_node);

            // mgba_printf(MGBA_LOG_ERROR, "bfs checking neighbor(%d): %d (%d, %d)", i, scan_node, scan_node_pos.x,
            //             scan_node_pos.y);

            // try to update shortest path (nodedist)
            if (cc_hashtable_contains_key(nodedist, &scan_node)) {
                // this node has been seen before, let's look at the stored shortest dist
                int* node_stored_shortest_dist;
                cc_hashtable_get(nodedist, &scan_node, (void*)&node_stored_shortest_dist);

                // if the current dist is less, store that instead
                if (scan_node_dist < *node_stored_shortest_dist) {
                    // mgba_printf(MGBA_LOG_ERROR, "nodedist shortest dist: %d -> %d", *node_stored_shortest_dist,
                    //             scan_node_dist);
                    *node_stored_shortest_dist = scan_node_dist;
                } else {
                    // we can update our current value for dist
                    scan_node_dist = *node_stored_shortest_dist;
                }
            }

            // make sure this tile in range
            if (board_dist(start_tx, start_ty, scan_node_pos.x, scan_node_pos.y) > range)
                continue;

            // make sure this tile is walkable
            Terrain terrain = board_get_terrain(scan_node);
            if (terrain != TERRAIN_GROUND)
                continue;

            // check if visited
            if (!cc_hashset_contains(visited, &scan_node)) {
                // mgba_printf(MGBA_LOG_ERROR, "bfs queuing neighbor(%d): %d (%d, %d)", i, scan_node, scan_node_pos.x,
                //             scan_node_pos.y);

                // put in storage, then add to queues
                BFSVisitStorage* storage_slot = &visit_tile_storage[visit_tile_storage_index];

                // set storage slot values
                storage_slot->tile_id = scan_node;
                storage_slot->dist = scan_node_dist;

                // ensure pos mem storage has space
                visit_tile_storage_index++;
                if (visit_tile_storage_index >= visit_tile_storage_size) {
                    mgba_printf(MGBA_LOG_ERROR, "bfs error, pos mem out of space");
                    return -1;
                }

                // now add to lists
                cc_deque_add_first(queue, &storage_slot->tile_id);
                cc_hashset_add(visited, &storage_slot->tile_id);
                cc_hashtable_add(nodedist, &storage_slot->tile_id, &storage_slot->dist);
            } else {
                // mgba_printf(MGBA_LOG_ERROR, "bfs already visited neighbor(%d): %d (%d, %d)", i, scan_node,
                //             scan_node_pos.x, scan_node_pos.y);
            }
        }
    }

    // copy visited data to pos buf
    CC_HashSetIter visited_iter;
    cc_hashset_iter_init(&visited_iter, visited);
    void* visited_iter_next;
    while (cc_hashset_iter_next(&visited_iter, &visited_iter_next) != CC_ITER_END) {
        int iter_val = *(int*)visited_iter_next;
        // mgba_printf(MGBA_LOG_ERROR, "visited iter: %d", iter_val);

        int scan_tid = iter_val;
        VPos16 scan_pos = board_util_tile_id_to_pos(scan_tid);

        // ensure not starting point
        if (scan_pos.x == start_tx && scan_pos.y == start_ty)
            continue;
        // ensure on board
        if (!board_util_is_on_board(scan_pos.x, scan_pos.y))
            continue;

        // // make sure no other pawn is there
        // if (board_get_pawn(BOARD_POS(scan_pos.x, scan_pos.y)))
        //     continue;

        pos_buf[pos_buf_ix] = scan_pos;
        pos_buf_ix++;

        // if pos buf is full, leave
        if (pos_buf_ix >= pos_buf_len - 1)
            return pos_buf_ix;
    }

    // // scan in square
    // for (int i = -range; i <= range; i++) {
    //     for (int j = -range; j <= range; j++) {
    //         if (i == 0 && j == 0)
    //             continue;

    //         int scan_tx = start_tx + i;
    //         int scan_ty = start_ty + j;
    //         if (!board_util_is_on_board(scan_tx, scan_ty))
    //             continue;

    //         if (board_dist(start_tx, start_ty, scan_tx, scan_ty) > range)
    //             continue;

    //         // // make sure no other pawn is there
    //         // if (board_get_pawn(BOARD_POS(scan_tx, scan_ty)))
    //         //     continue;

    //         // this is in range
    //         pos_buf[pos_buf_ix] = (VPos16){.x = scan_tx, .y = scan_ty};
    //         pos_buf_ix++;

    //         // if pos buf is full, leave
    //         if (pos_buf_ix >= pos_buf_len - 1)
    //             return pos_buf_ix;
    //     }
    // }

    // clean up
    cc_hashset_destroy(visited);
    cc_deque_destroy(queue);
    cc_hashtable_destroy(nodedist);

    return pos_buf_ix;
}

BOOL pawn_util_is_valid_move(pawn_gid_t pawn_gid, VPos16 start_pos, VPos16 end_pos) {
    ClassData* class_data = pawn_get_classdata(pawn_gid);

    int pawn_max_move = class_data->move;

    // check dist from start to end tiles
    int start_end_dist = board_dist(start_pos.x, start_pos.y, end_pos.x, end_pos.y);

    // check if dist exceeds max move
    if (start_end_dist > pawn_max_move)
        return FALSE;

    return TRUE;
}

BOOL pawn_util_is_valid_interaction(pawn_gid_t pawn1_gid, VPos16 pawn1_pos, pawn_gid_t pawn2_gid, VPos16 pawn2_pos) {
    // ClassData* class_data = pawn_get_classdata(pawn_gid);

    // int pawn_max_move = class_data->move;

    // // check dist from start to end tiles
    // int start_end_dist = board_dist(start_pos.x, start_pos.y, end_pos.x, end_pos.y);

    // // check if dist exceeds max move
    // if (start_end_dist > pawn_max_move)
    //     return FALSE;

    return TRUE;
}