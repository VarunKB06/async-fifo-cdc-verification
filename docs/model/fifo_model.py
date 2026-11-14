#!/usr/bin/env python3
"""Cycle/event-accurate PYTHON model of the async FIFO equations (NOT the RTL, NOT a simulator run).
Used only to sanity-check the algorithm, the strict-time scoreboard rules and the synchronizer latency bounds."""
import random, sys

def gray(x): return (x >> 1) ^ x

def run(AW, ST, wper, rper, wph, rph, wp, rp, ncyc, seed):
    rnd = random.Random(seed)
    D = 1 << AW; M = (1 << (AW + 1)) - 1
    mem = [0] * D
    wbin = wgray = rbin = rgray = 0; full = 0; empty = 1
    r2w = [0] * ST; w2r = [0] * ST            # synchronizer stages (index ST-1 = output)
    wr_log = []; rd_log = []                  # (time, data) accepted
    wr_t = []; rd_t = []
    errors = []; full_stuck = 0; empty_stuck = 0; max_fs = 0; max_es = 0
    wen = ren = 0; din = 0
    wr_edges = []; rd_edges = []
    t_end = ncyc * max(wper, rper)
    wnext = wph; rnext = rph
    ref = []; wcnt = 0; rcnt = 0
    wlast = -1; rlast = -1
    wr_cnt_t = []; rd_cnt_t = []
    while True:
        t = min(wnext, rnext)
        if t > t_end: break
        wedge = (t == wnext); redge = (t == rnext)
        # ---- pre-edge snapshot values
        s_full, s_empty = full, empty
        s_wbin, s_wgray, s_rbin, s_rgray = wbin, wgray, rbin, rgray
        s_r2w, s_w2r = list(r2w), list(w2r)
        n = {}
        if wedge:
            ack = wen and not s_full
            # scoreboard (writer): reads strictly before t
            rb = rcnt - (1 if (rcnt > 0 and rlast == t) else 0)
            occw = wcnt - rb
            if occw >= D and not s_full: errors.append((t, 'full not set'))
            if s_full and occw < D: full_stuck += 1
            else: full_stuck = 0
            max_fs = max(max_fs, full_stuck)
            if ack:
                if occw >= D: errors.append((t, 'overflow'))
                else: ref.append(din); wcnt += 1; wlast = t
            wb_n = (s_wbin + (1 if ack else 0)) & M
            wg_n = gray(wb_n)
            rgs = s_r2w[ST - 1]
            full_n = int(wg_n == (rgs ^ (3 << (AW - 1))))
            if ack: mem[s_wbin & (D - 1)] = din     # memory write (pre-edge address, new data)
            n['w'] = (wb_n, wg_n, full_n, [s_rgray] + s_r2w[:-1])
        if redge:
            valid = ren and not s_empty
            wb = wcnt - (1 if (wcnt > 0 and wlast == t) else 0)
            avail = wb - rcnt
            if avail <= 0 and not s_empty: errors.append((t, 'empty not set'))
            if s_empty and avail > 0: empty_stuck += 1
            else: empty_stuck = 0
            max_es = max(max_es, empty_stuck)
            if valid:
                if avail <= 0: errors.append((t, 'underflow'))
                else:
                    exp = ref[rcnt]; rcnt += 1; rlast = t
                    if mem[s_rbin & (D - 1)] != exp: errors.append((t, 'mismatch'))
            rb_n = (s_rbin + (1 if valid else 0)) & M
            rg_n = gray(rb_n)
            wgs = s_w2r[ST - 1]
            empty_n = int(rg_n == wgs)
            n['r'] = (rb_n, rg_n, empty_n, [s_wgray] + s_w2r[:-1])
        # ---- commit
        if wedge:
            wbin, wgray, full, r2w = n['w']
            wnext += wper
            wen = rnd.random() < wp; din = rnd.randrange(256)
        if redge:
            rbin, rgray, empty, w2r = n['r']
            rnext += rper
            ren = rnd.random() < rp
    return errors, max_fs, max_es, wcnt, rcnt

if __name__ == '__main__':
    tot_err = 0; mfs = 0; mes = 0; runs = 0
    rnd = random.Random(1)
    for i in range(400):
        AW = rnd.choice([2, 3, 4]); ST = rnd.choice([2, 3])
        wper = rnd.choice([1000, 2000, 5000, 10000, 13334, 7333, 10000])
        rper = rnd.choice([1000, 2000, 5000, 10000, 13334, 7333, 10000])
        wph = rnd.choice([0, 0, 137, 2500]); rph = rnd.choice([0, 0, 91, 2500])
        wp = rnd.choice([0.1, 0.5, 0.9, 1.0]); rp = rnd.choice([0.1, 0.5, 0.9, 1.0])
        e, fs, es, w, r = run(AW, ST, wper, rper, wph, rph, wp, rp, 600, i)
        runs += 1; tot_err += len(e)
        mfs = max(mfs, fs - 0); mes = max(mes, es)
        if e: print("ERR", AW, ST, wper, rper, wph, rph, wp, rp, e[:3])
        # latency bound per ST
        if fs > ST + 1 or es > ST + 1: print("LAT>", ST, fs, es, wper, rper)
    print("runs", runs, "errors", tot_err, "max full_stuck", mfs, "max empty_stuck", mes)
