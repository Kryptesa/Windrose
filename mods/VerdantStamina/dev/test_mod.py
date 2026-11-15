"""Run the shipping Lua display model under Lua 5.4, without loading the game."""
import math
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/python"))
from lupa.lua54 import LuaRuntime


class StaminaModelTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("package.path = ... .. '/?.lua;' .. package.path", (ROOT / "mods/VerdantStamina/Scripts").as_posix())
        self.core = self.lua.eval("require('core')")[0]
        self.config = self.lua.eval("require('config')")[0]
        self.core.validate(self.config)

    def test_all_shipping_lua_parses(self):
        for path in (ROOT / "mods").rglob("*.lua"):
            self.lua.execute("assert(load(...))", path.read_text(encoding="utf-8"))

    def test_existing_upgrade_is_not_mistaken_for_base(self):
        state = self.core.sample(None, 240, 240, 1 / 60, self.config)
        rings = self.core.rings(240, self.config)
        self.assertEqual(len(rings), 2)
        self.assertEqual(rings[1].capacity, 150)
        self.assertEqual(rings[2].available, 90)
        self.assertAlmostEqual(self.core.fill(rings[2], state.shown), 0.6)

    def test_capacity_and_fill_conserve_all_stamina(self):
        for maximum in (75, 150, 150.25, 200, 300, 340, 1050, 2000):
            rings = self.core.rings(maximum, self.config)
            self.assertLessEqual(len(rings), math.ceil(maximum / self.config.base_capacity))
            self.assertAlmostEqual(sum(rings[i].available for i in range(1, len(rings) + 1)), maximum)
            for value in (0, 1, maximum * 0.37, maximum):
                represented = sum(self.core.fill(rings[i], value) * rings[i].capacity for i in range(1, len(rings) + 1))
                self.assertAlmostEqual(represented, value)

    def test_outer_reserve_spent_before_base(self):
        rings = self.core.rings(340, self.config)
        self.assertEqual(self.core.fill(rings[1], 200), 1)
        self.assertAlmostEqual(self.core.fill(rings[2], 200), 50 / 150)
        self.assertEqual(self.core.fill(rings[3], 200), 0)

    def test_smoothing_is_continuous_and_frame_rate_independent(self):
        values = []
        for fps in (30, 60, 144):
            state = self.core.sample(None, 150, 150, 0, self.config)
            for _ in range(fps):
                previous = state.shown
                state = self.core.sample(state, 50, 150, 1 / fps, self.config)
                self.assertGreaterEqual(state.shown, 50)
                self.assertLessEqual(state.shown, previous)
            values.append(state.shown)
        self.assertLess(max(values) - min(values), 0.0001)
        state = self.core.sample(None, 150, 150, 0, self.config)
        after = self.core.sample(state, 120, 150, 1 / 60, self.config)
        self.assertGreater(after.shown, 120)
        self.assertLess(after.shown, 150)

    def test_zero_and_capacity_changes_do_not_show_phantom_stamina(self):
        state = self.core.sample(None, 150, 150, 0, self.config)
        self.assertEqual(self.core.sample(state, 0, 150, 1 / 60, self.config).shown, 0)
        lowered = self.core.sample(state, 50, 75, 1 / 60, self.config)
        self.assertEqual(lowered.shown, 50)
        low = self.core.sample(state, 10, 150, 1 / 60, self.config)
        self.assertTrue(low.critical)
        self.assertGreater(low.shown, 10)

    def test_partial_arc_boundary_moves_continuously(self):
        self.assertEqual(self.core.arc_halves(0), (0, 0))
        self.assertEqual(self.core.arc_halves(0.5), (180, 0))
        self.assertEqual(self.core.arc_halves(1), (180, 180))
        a=self.core.arc_halves(0.001)[0]
        b=self.core.arc_halves(0.002)[0]
        self.assertAlmostEqual(b-a,0.36)
        self.assertAlmostEqual(self.core.arc_halves(0.500001)[1],0.00036)

    def test_zelda_proportions_and_distinct_outer_ring_weights(self):
        rings=self.core.rings(450,self.config)
        self.assertEqual(len(rings),3)
        self.assertEqual(rings[1].radius+rings[1].thickness/2,23.5)
        self.assertAlmostEqual(rings[1].radius-rings[1].thickness/2,11.8)
        self.assertAlmostEqual(rings[1].thickness,9*1.3)
        self.assertEqual(self.config.ui_scale,1)
        self.assertGreater(rings[2].thickness,rings[3].thickness)
        self.assertEqual(rings[2].thickness,rings[1].thickness/2)
        self.assertEqual(rings[3].thickness,rings[1].thickness/3)
        for i in (2,3):
            gap=(rings[i].radius-rings[i].thickness/2)-(rings[i-1].radius+rings[i-1].thickness/2)
            self.assertEqual(gap,self.config.ring_gap)

    def test_soft_cut_edge_covers_the_retracted_hard_clip(self):
        rings=self.core.rings(450,self.config)
        for i in range(1,len(rings)+1):
            ring=rings[i]
            inner=ring.radius-ring.thickness/2
            outer=ring.radius+ring.thickness/2
            for fraction in (0.001,0.1,0.333,0.499,0.5,0.501,0.777,0.999):
                e=self.core.arc_edges(fraction,inner,self.config.edge_softness)
                self.assertEqual(e.cap,1 if fraction<=0.5 else 2)
                angle=fraction*360 if e.cap==1 else (fraction-0.5)*360
                body=e.right if e.cap==1 else e.left
                if body>0:
                    offset=math.radians(angle-body)
                    # Main body's hard cut must lie inside the cap's fully
                    # opaque area at both radial boundaries, not in a gap.
                    for radius in (inner,outer):
                        x=-radius*math.sin(offset)
                        self.assertLessEqual(x,-self.config.edge_softness/2)
                        self.assertGreaterEqual(x,-5+self.config.edge_softness)
        self.assertEqual(self.core.arc_edges(0,9.5,1.25).cap,0)
        self.assertEqual(self.core.arc_edges(1,9.5,1.25).cap,0)

    def test_invalid_data_rejected(self):
        for current, maximum in ((float("nan"), 150), (5, float("inf")), (5, 0), (5, -2)):
            self.assertIsNone(self.core.sample(None, current, maximum, 0.016, self.config))
        self.assertEqual(self.core.sample(None, -2, 150, 0.016, self.config).actual, 0)
        self.assertEqual(self.core.sample(None, 900, 150, 0.016, self.config).actual, 150)

    def test_warning_thresholds_and_continuous_spatial_tint(self):
        amounts=[]
        for fraction in (1,0.30,0.25,0.20,0.15,0.10,0):
            s=self.core.sample(None,fraction*150,150,0,self.config)
            amounts.append(s.warning)
            tint=self.core.tint(s,self.config)
            self.assertAlmostEqual(tint.A,1)
        self.assertEqual(amounts[:2],[0,0])
        self.assertEqual(amounts[-2:],[1,1])
        self.assertEqual(amounts,sorted(amounts))
        self.assertAlmostEqual(amounts[3],0.5)
        above=self.core.sample(None,0.300001*150,150,0,self.config)
        below=self.core.sample(None,0.299999*150,150,0,self.config)
        self.assertLess(abs(above.warning-below.warning),1e-8)

    def test_warning_eases_in_and_out_independently_of_frame_rate(self):
        ends=[]
        for fps in (30,60,144):
            state=self.core.sample(None,150,150,0,self.config)
            first=self.core.sample(state,5,150,1/fps,self.config)
            self.assertGreater(first.warning,0)
            self.assertLess(first.warning,1)
            self.assertTrue(first.critical)
            for _ in range(fps):state=self.core.sample(state,5,150,1/fps,self.config)
            ends.append(state.warning)
            regen=self.core.sample(state,150,150,1/fps,self.config)
            self.assertGreater(regen.warning,0)
            self.assertLess(regen.warning,state.warning)
        self.assertLess(max(ends)-min(ends),0.0001)

    def test_adapter_creation_updates_toggle_rebuild_and_failure_restore(self):
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_native_source_adapter_contracts(self):
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/source_reader_harness.lua').read_text(encoding='utf-8'))

    def test_menu_lifecycle_rebinds_a_recreated_widget(self):
        self.lua.globals().lifecycle_case='new_widget'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_live_layout_tracks_native_position_anchors_pivot_and_order(self):
        self.lua.globals().layout_case='late_position'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_live_layout_recenters_after_source_size_finishes_initializing(self):
        self.lua.globals().layout_case='late_size'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_new_widget_notification_binds_before_periodic_discovery(self):
        self.lua.globals().lifecycle_case='new_widget_immediate'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_new_widget_notification_waits_for_nonzero_layout_then_binds_next_frame(self):
        self.lua.globals().lifecycle_case='new_widget_delayed_size'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_construction_notification_waits_for_readiness_and_survives_reload_once(self):
        self.lua.execute('''
            local registrations=0
            function NotifyOnNewObject(_,fn) registrations=registrations+1;creation_callback=fn end
            function ExecuteInGameThread() error('no cross-thread callback registration') end
            function LoopAsync() error('no async worker') end
            local first=require('lifecycle')
            first.start(function() end)
            local widget={IsValid=function() return true end,GetAddress=function() return 7 end,
                          GetFullName=function() return 'WBP_StaminaRing_C Test' end}
            creation_callback(widget)
            local ready,attached=false,0
            first.drain(function() if ready then attached=attached+1;return true end end)
            assert(attached==0,'UObject creation is not complete widget initialization')
            ready=true
            first.drain(function(_,age) assert(age==2);attached=attached+1;return true end)
            assert(attached==1)
            first.stop()
            creation_callback(widget)
            first.drain(function() error('disabled module must not receive candidates') end)
            package.loaded.lifecycle=nil
            local replacement=require('lifecycle')
            replacement.start(function() end)
            assert(registrations==1,'hot reload must reuse the class-specific native subscription')
            creation_callback(widget)
            replacement.drain(function() attached=attached+1;return true end)
            assert(attached==2,'the original native callback must feed the reloaded app')
        ''')

    def test_menu_lifecycle_rebinds_a_replaced_stock_image(self):
        self.lua.globals().lifecycle_case='new_image'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_menu_lifecycle_hides_stock_paint_after_native_reset(self):
        self.lua.globals().lifecycle_case='paint_reset'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_menu_lifecycle_recovers_a_reparented_image(self):
        self.lua.globals().lifecycle_case='new_parent'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_menu_lifecycle_recovers_a_detached_canvas(self):
        self.lua.globals().lifecycle_case='detached_panel'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def test_menu_lifecycle_waits_for_widget_construction_without_stopping(self):
        self.lua.globals().lifecycle_case='pending_widget'
        self.lua.execute((ROOT / 'mods/VerdantStamina/dev/runtime_harness.lua').read_text(encoding='utf-8'))

    def source_snapshot(self, permanent_endurance, temporary_endurance=0, direct=0, talent=50):
        # Explicit marginal formula is only fixture construction; assertions below
        # use independent expected observed/datamined totals and soft-cap examples.
        total_e=permanent_endurance+temporary_endurance
        bonus=4.59*min(total_e,20)+3.4425*min(max(total_e-20,0),20)+2.295*max(total_e-40,0)
        effects=[{'name':'Permanent stat/equipment','duration':-1,'modifiers':[
            {'attribute':'Endurance','operation':0,'magnitude':permanent_endurance}]},
            {'name':'Native derived stamina','duration':-1,'modifiers':[
                {'attribute':'MaxStamina','operation':0,'magnitude':bonus}]},
            {'name':'Talent','duration':-1,'modifiers':[
                {'attribute':'MaxStamina','operation':0,'magnitude':talent}]}]
        if temporary_endurance:
            effects.append({'name':'Coffee','duration':1800,'modifiers':[
                {'attribute':'Endurance','operation':0,'magnitude':temporary_endurance}]})
        if direct:
            effects.append({'name':'Fruit','duration':420,'modifiers':[
                {'attribute':'MaxStamina','operation':0,'magnitude':direct}]})
        return self.lua.table_from({'maximum':150+talent+bonus+direct,'endurance':total_e,
            'endurance_base':0,'maximum_base':150,'effects':effects,'formula':{
                'AttributePointValue':3,'AttributeUpperLimit':176,'EffectivenessC1':1.53,
                'EffectivenessC2':1.1475,'EffectivenessC3':.765,'PivotValue1':20,'PivotValue2':40}},recursive=True)

    def test_sources_keep_upgrades_and_equipment_but_remove_both_food_kinds(self):
        model=self.lua.eval("require('source_model')")[0]
        s=model.resolve(self.source_snapshot(60,20,160))
        self.assertAlmostEqual(s.maximum,612.45)
        self.assertAlmostEqual(s.permanent_maximum,406.55)
        self.assertAlmostEqual(s.temporary_maximum,205.9)
        self.assertEqual(s.permanent_endurance,60)
        self.assertEqual(s.temporary_endurance,20)
        self.assertEqual(s.temporary_direct_stamina,160)
        without=model.resolve(self.source_snapshot(4,talent=35))
        self.assertAlmostEqual(without.permanent_maximum,203.36)
        self.assertAlmostEqual(without.temporary_maximum,0)

    def test_source_subtraction_respects_endurance_soft_caps(self):
        model=self.lua.eval("require('source_model')")[0]
        s=model.resolve(self.source_snapshot(18,20))
        self.assertAlmostEqual(s.maximum,353.765)
        self.assertAlmostEqual(s.permanent_maximum,282.62)
        self.assertAlmostEqual(s.temporary_maximum,71.145)

    def test_incomplete_or_unsupported_native_sources_fail_closed(self):
        model=self.lua.eval("require('source_model')")[0]
        for fault in ('maximum','endurance','operation'):
            s=self.source_snapshot(60,20,160)
            if fault=='operation':s.effects[1].modifiers[1].operation=1
            else:s[fault]+=10
            with self.assertRaises(Exception):model.resolve(s)

    def test_yellow_reserve_spends_first_and_two_groups_conserve_all_stamina(self):
        model=self.lua.eval("require('source_model')")[0]
        s=model.resolve(self.source_snapshot(60,20,160))
        layout=self.core.layout(s.maximum,self.config,s)
        green=[layout[i] for i in range(1,len(layout)+1) if layout[i].kind=='permanent']
        yellow=[layout[i] for i in range(1,len(layout)+1) if layout[i].kind=='temporary']
        self.assertEqual((len(green),len(yellow)),(3,1))
        green_edge=green[-1].ring.radius+green[-1].ring.thickness/2
        yellow_right=yellow[-1].x+(yellow[-1].ring.radius+yellow[-1].ring.thickness/2)*yellow[-1].scale
        self.assertAlmostEqual(-green_edge-yellow_right,self.config.temporary_group_gap)
        for current in (0,75,400,406.55,430,612.45):
            p,t=model.partition(current,s)
            represented=sum(self.core.fill(e.ring,p)*e.ring.capacity for e in green)
            represented+=sum(self.core.fill(e.ring,t)*e.ring.capacity for e in yellow)
            self.assertAlmostEqual(represented,current)
            if current<=s.permanent_maximum:self.assertEqual(t,0)
            else:self.assertAlmostEqual(p,s.permanent_maximum)

    def test_initial_green_ring_is_larger_until_a_permanent_upgrade(self):
        base=self.lua.table_from({'permanent_maximum':150,'temporary_maximum':160})
        upgraded=self.lua.table_from({'permanent_maximum':170,'temporary_maximum':0})
        a=self.core.layout(310,self.config,base)
        b=self.core.layout(170,self.config,upgraded)
        self.assertEqual(a[1].scale,self.config.initial_ring_scale)
        self.assertEqual(b[1].scale,1)

    def test_new_ring_threshold_hides_slivers_without_losing_capacity(self):
        for maximum,count in ((150.25,1),(159.99,1),(160,2),(300.01,2),(309.99,2),(310,3),(495,4)):
            rings=self.core.rings(maximum,self.config)
            self.assertEqual(len(rings),count)
            for current in (maximum,maximum*.6,1):
                shown=sum(self.core.fill(rings[i],current)*rings[i].capacity for i in range(1,len(rings)+1))
                self.assertAlmostEqual(shown,current)
        rings=self.core.rings(495,self.config)
        self.assertEqual(rings[4].thickness,rings[3].thickness)

    def test_visual_test_maps_real_percentage_without_changing_real_attributes(self):
        self.config.visual_test_mode=True
        real_maximum=203.36
        for fraction in (0,0.1,0.5,0.9,1):
            current=real_maximum*fraction
            shown,maximum,sources=self.core.display_values(current,real_maximum,self.config,None)
            self.assertAlmostEqual(maximum,600)
            self.assertAlmostEqual(shown,600*fraction)
            self.assertTrue(sources.display_test)
            self.assertFalse(sources.verified)
            layout=self.core.layout(maximum,self.config,sources)
            self.assertEqual(len(layout),4)
            self.assertEqual(real_maximum,203.36)
        self.config.visual_test_mode=False
        current,maximum,sources=self.core.display_values(100,203.36,self.config,None)
        self.assertEqual((current,maximum,sources),(100,203.36,None))

    def test_scheduler_never_crosses_the_async_lua_boundary(self):
        # Matches the native failure boundary: old LoopAsync -> ExecuteInGameThread
        # races two Lua VMs sharing the same registry. The timer must be native.
        self.lua.execute('''
            local frames,toggles=0,0
            package.preload.app=function() return {
                frame=function() frames=frames+1 end,
                stop=function() end,
                toggle=function() toggles=toggles+1 end,
            } end
            function LoopAsync() error('unsafe async scheduler') end
            function ExecuteInGameThread() error('unexpected cross-thread callback registration') end
            function LoopInGameThreadAfterFrames(n,fn) assert(n==1);native_frame=fn;return 1 end
            function RegisterKeyBind(key,fn) end
            function scheduler_counts() return frames,toggles end
        ''')
        self.lua.execute((ROOT / 'mods/VerdantStamina/Scripts/main.lua').read_text(encoding='utf-8'))
        for _ in range(10):
            self.lua.globals().native_frame()
        self.assertEqual(self.lua.globals().scheduler_counts(), (10, 0))

    def test_reload_invalidates_ue4ss_compiled_module_cache(self):
        # UE4SS 4.0 custom searcher caches compiled loaders separately from
        # package.loaded, keyed by normalized absolute filename (LuaMod.cpp).
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temp:
            scripts=Path(temp)/'Scripts';scripts.mkdir()
            app=scripts/'app.lua'
            app.write_text('return {revision=1,frame=function() active_revision=1 end,stop=function() end}',encoding='utf-8')
            main=scripts/'main.lua'
            main.write_text((ROOT/'mods/VerdantStamina/Scripts/main.lua').read_text(encoding='utf-8'),encoding='utf-8')
            self.lua.globals().test_scripts=scripts.as_posix()
            self.lua.execute('''
                ue4ss_loaded_modules={}
                ue4ss_loaded_modules['C:/other-mod/Scripts/app.lua']=function() end
                test_keys={}
                table.insert(package.searchers,1,function(name)
                    if name~='app' then return 'test module not found' end
                    local path=test_scripts..'/app.lua'
                    if not ue4ss_loaded_modules[path] then ue4ss_loaded_modules[path]=assert(loadfile(path)) end
                    return ue4ss_loaded_modules[path]
                end)
                function LoopInGameThreadAfterFrames(_,fn) test_frame=fn end
                function RegisterKeyBind(key,fn) test_keys[key]=fn end
            ''')
            self.lua.execute('assert(loadfile(...))()',main.as_posix())
            self.lua.globals().test_frame()
            self.assertEqual(self.lua.globals().active_revision,1)
            app.write_text('return {revision=2,frame=function() active_revision=2 end,stop=function() end}',encoding='utf-8')
            self.lua.execute('test_keys[0x79]();test_frame()')
            self.assertEqual(self.lua.globals().active_revision,2,'F10 must execute the edited source, not the old UE4SS loader')
            self.assertTrue(self.lua.eval("ue4ss_loaded_modules['C:/other-mod/Scripts/app.lua']~=nil"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
