module scn.board.ui;

import core.stdc.string;
import core.stdc.stdio;
import dusk;
import tonc;
import libgba.maxmod;
import res;
import dusk.contrib.mgba;
import typ.vpos;
import scn.board;
import game;

// get the pawn under the cursor
Pawn* get_cursor_pawn() {
    if (!cursor_shown)
        return null;
    return board_get_pawn(BOARD_POS(cursor_pos.x, cursor_pos.y));
}

// get the gid of the pawn that is currently selected
pawn_gid_t get_clicked_pawn_gid() {
    if (!cursor_click)
        return -1;
    return board_get_tile(BOARD_POS(cursor_click_pos.x, cursor_click_pos.y)).pawn_gid;
}

// get the pawn that is currently selected
Pawn* get_clicked_pawn() {
    if (!cursor_click)
        return null;
    return board_get_pawn(BOARD_POS(cursor_click_pos.x, cursor_click_pos.y));
}

// logic for when the clicked cursor is used to move a pawn
void on_cursor_click_move(VPos16 dest_pos) {
    // get the already selected pawn
    auto sel_pawn_gid = get_clicked_pawn_gid();
    ClassData sel_pawn_cd = pawn_get_classdata(sel_pawn_gid);
    VPos16 sel_pawn_pos = cursor_click_pos;

    // now check the dest tile
    int dest_tid = BOARD_POS(dest_pos.x, dest_pos.y);
    BoardTile* dest_tile = board_get_tile(dest_tid);

    // check if there's a pawn in the dest tile
    if (dest_tile.pawn_gid >= 0) {
        // there is a pawn there
        pawn_gid_t dest_pawn_gid = dest_tile.pawn_gid;

        int ir = sel_pawn_cd.interact_range;

        // are we within interact range (ir)?
        bool within_ir = board_dist(sel_pawn_pos.x, sel_pawn_pos.y, dest_pos.x, dest_pos.y) <= ir;

        // tid of intermediate tile
        int interact_itmdt_tid = -1;

        if (!within_ir) {
            // try to find to the closest tile within ir
            // use that tile as the intermediate

            // initialize to starting tile
            int closest_neighbor_tid = -1;
            int closest_neighbor_dist = -1;

            // check all neighbors
            for (int nx = -ir; nx <= ir; nx++) {
                for (int ny = -ir; ny <= ir; ny++) {
                    // get neighbor tile info
                    // VPos16 nb_pos = (VPos16){.x = dest_pos.x + nx, .y = dest_pos.y + ny};
                    auto nb_pos = VPos16(cast(u16)(dest_pos.x + nx), cast(u16)(dest_pos.y + ny));
                    int nb_tid = POS_TO_TID(nb_pos);

                    // ensure that from this tile, we're within ir
                    if (board_dist(nb_pos.x, nb_pos.y, dest_pos.x, dest_pos.y) > ir)
                        continue; // out of range

                    // make sure this tile is walkable
                    if (!board_util_is_walkable(nb_pos.x, nb_pos.y))
                        continue;

                    // make sure nobody else is standing there!
                    if (board_get_pawn(nb_tid) != null)
                        continue;

                    // test distance from start pos
                    int nb_test_dist = board_dist(cursor_click_pos.x, cursor_click_pos.y,
                        nb_pos.x, nb_pos.y);

                    if (closest_neighbor_tid < 0 || nb_test_dist < closest_neighbor_dist) {
                        closest_neighbor_dist = nb_test_dist;
                        closest_neighbor_tid = nb_tid;
                    }
                }
            }

            if (closest_neighbor_tid > 0) {
                // the intermediate is the most convenient neighbor
                interact_itmdt_tid = closest_neighbor_tid;
            }
        } else {
            // we are already within ir
            interact_itmdt_tid = POS_TO_TID(sel_pawn_pos);
        }

        if (interact_itmdt_tid > 0) {
            // we have a valid intermediate
            VPos16 interact_itmdt_pos = board_util_tid_to_pos(interact_itmdt_tid);

            // move our pawn to the intermediate
            animate_pawn_move(sel_pawn_gid, cursor_click_pos, interact_itmdt_pos);
            // flash the dest pawn

            bool ally = pawn_util_on_same_team(sel_pawn_gid, dest_pawn_gid);
            if (ally) {
                sfx_play_interact_ally();
            } else {
                sfx_play_interact_foe();
            }
            animate_pawn_flash(dest_pawn_gid, sel_pawn_gid, ally);

            // interact with the pawn
            mgba_printf(MGBALogLevel.INFO, "interact (me: %d) with pawn (%d)", sel_pawn_gid, dest_tile
                    .pawn_gid);

            // request_step = true; // request step
        } else {
            // we can't reach this pawn, give up
            mgba_printf(MGBALogLevel.ERROR, "we couldn't reach this pawn");
        }
    } else {
        // request a move anim
        mgba_printf(MGBALogLevel.INFO, "move pawn (%d) to (%d, %d)", sel_pawn_gid, dest_pos.x,
            dest_pos.y);
        sfx_play_move();
        animate_pawn_move(sel_pawn_gid, cursor_click_pos, dest_pos);
    }

    // now unclick and set dirty
    cursor_click = false;
    set_ui_dirty();

    return; // done
}

void on_cursor_try_click(VPos16 try_click_pos) {
    if (cursor_click) {
        // a pawn is already selected

        // get the already selected pawn
        auto sel_pawn_gid = get_clicked_pawn_gid();

        bool try_click_is_valid_move = false;

        // then check if the click is within the range
        for (int i = 0; i < cache_range_vec.length; i++) {
            // for each tile that's in range
            VPos16 withinrange_pos = cache_range_vec[i];
            if (try_click_pos.x == withinrange_pos.x && try_click_pos.y == withinrange_pos.y) {
                // this click target is within range

                // ensure that the move is valid
                bool is_move_valid = pawn_util_is_valid_move(sel_pawn_gid, cursor_click_pos, try_click_pos);

                if (!is_move_valid) {
                    // this move is invalid
                    mgba_printf(MGBALogLevel.ERROR, "this move from (%d, %d) to (%d, %d) is invalid",
                        cursor_click_pos.x, cursor_click_pos.y, try_click_pos.x, try_click_pos.y);
                    break;
                }

                try_click_is_valid_move = true;
            }
        }

        if (try_click_is_valid_move) {
            on_cursor_click_move(try_click_pos);
            return;
        }

        // if we got here, then the click wasn't within range
        // unclick
        cursor_click = false;
        set_ui_dirty();
        sfx_play_cant();
    } else if (get_cursor_pawn()) {
        // nothing is currently selected, but our cursor is over a pawn

        // check if this pawn is valid to be selected
        BoardTile* tile = board_get_tile(BOARD_POS(cursor_pos.x, cursor_pos.y));
        auto hover_pawn_gid = tile.pawn_gid;
        Pawn* hover_pawn = get_cursor_pawn();

        // we can only move via cursor if the turn is the human player's
        if (HUMAN_PLAYER_TEAM >= 0 && game_util_whose_turn() != HUMAN_PLAYER_TEAM)
            return;

        // ensure it is our turn
        if (!game_util_is_my_turn(hover_pawn_gid))
            return;

        // ensure the pawn has not already moved this turn
        if (pawn_util_moved_this_turn(hover_pawn))
            return;

        // set that pawn as clicked
        cursor_click = true;
        cursor_click_pos = try_click_pos;
        pawn_move_range_dirty = true;
        set_ui_dirty();

        sfx_play_click();
    }
}

void on_try_move_cursor(int mx, int my) {
    // move cursor
    cursor_pos.x += mx;
    cursor_pos.y += my;

    // ensure cursor position is clamped
    // if we go out of range, we have to both clamp and adjust window
    int board_scroll_max = game_state.board_size - BOARD_SCROLL_WINDOW;

    // scroll window along with cursor
    int cursor_vx = cursor_pos.x - board_scroll_x;
    int cursor_vy = cursor_pos.y - board_scroll_y;

    if (cursor_vx < 0) {
        board_scroll_x -= 1;
    }
    if (cursor_vx >= BOARD_SCROLL_WINDOW) {
        board_scroll_x += 1;
    }
    if (cursor_vy < 0) {
        board_scroll_y -= 1;
    }
    if (cursor_vy >= BOARD_SCROLL_WINDOW) {
        board_scroll_y += 1;
    }

    // global clamping

    if (cursor_pos.x < 0) {
        cursor_pos.x = game_state.board_size - 1;
        board_scroll_x = board_scroll_max;
    }
    if (cursor_pos.x >= game_state.board_size) {
        cursor_pos.x = 0;
        board_scroll_x = 0;
    }
    if (cursor_pos.y < 0) {
        cursor_pos.y = game_state.board_size - 1;
        board_scroll_y = board_scroll_max;
    }
    if (cursor_pos.y >= game_state.board_size) {
        cursor_pos.y = 0;
        board_scroll_y = 0;
    }

    // cursor_click = false;

    // set ui fields to dirty/reset
    set_ui_dirty();
    sidebar_page = 0;

    sfx_play_scroll();
}
