/* SPDX-License-Identifier: MIT
 *
 * AwgChain pack 55: the three check boxes of the edit dialog.
 *
 * The first one used to be the upstream kill switch, which only rewrote
 * AllowedIPs and did nothing for a chain. It now drives our own kill switch,
 * and the configuration text is left alone.
 */

package ui

import (
	"github.com/lxn/walk"

	"github.com/amnezia-vpn/amneziawg-windows-client/manager"
)

// chainChecksBox makes the column that holds the three check boxes. It is
// called from the line that used to drop the first box straight into the row
// of buttons.
func chainChecksBox(dlg *EditDialog, parent walk.Container) walk.Container {
	box, err := walk.NewComposite(parent)
	if err != nil {
		return parent
	}
	layout := walk.NewVBoxLayout()
	layout.SetMargins(walk.Margins{0, 0, 0, 0})
	layout.SetSpacing(2)
	err = box.SetLayout(layout)
	if err != nil {
		return parent
	}
	dlg.chainChecks = box
	return box
}

// chainExtraChecks adds the IPv6 and local network boxes under the first one.
func chainExtraChecks(dlg *EditDialog) error {
	parent := dlg.chainChecks
	if parent == nil {
		return nil
	}

	var err error
	if dlg.chainIPv6CB, err = walk.NewCheckBox(parent); err != nil {
		return err
	}
	dlg.chainIPv6CB.SetText(chainCheckIPv6Label)
	dlg.chainIPv6CB.SetToolTipText(chainCheckIPv6Hint)

	if dlg.chainLANCB, err = walk.NewCheckBox(parent); err != nil {
		return err
	}
	dlg.chainLANCB.SetText(chainCheckLANLabel)
	dlg.chainLANCB.SetToolTipText(chainCheckLANHint)

	dlg.chainLoadChecks()
	return nil
}

// chainLoadChecks fills the three boxes from the manager. When the manager
// cannot be reached the local network stays allowed, because a remote
// desktop session is worth more than a tidy default.
func (dlg *EditDialog) chainLoadChecks() {
	settings := manager.ChainTunnelSettings{KillSwitch: true, BlockIPv6: true, AllowLAN: true}
	name := dlg.config.Name
	if name != "" {
		if saved, err := manager.IPCClientChainSettings(name); err == nil {
			settings = saved
		}
	}
	if dlg.blockUntunneledTrafficCB != nil {
		dlg.blockUntunneledTrafficCB.SetChecked(settings.KillSwitch)
	}
	if dlg.chainIPv6CB != nil {
		dlg.chainIPv6CB.SetChecked(settings.BlockIPv6)
	}
	if dlg.chainLANCB != nil {
		dlg.chainLANCB.SetChecked(settings.AllowLAN)
	}
}

// chainSaveChecks is called from Save, once the name of the tunnel is known.
func (dlg *EditDialog) chainSaveChecks(name string) {
	if dlg.blockUntunneledTrafficCB == nil || dlg.chainIPv6CB == nil || dlg.chainLANCB == nil {
		return
	}
	settings := manager.ChainTunnelSettings{
		KillSwitch: dlg.blockUntunneledTrafficCB.Checked(),
		BlockIPv6:  dlg.chainIPv6CB.Checked(),
		AllowLAN:   dlg.chainLANCB.Checked(),
	}
	err := manager.IPCClientChainSettingsSave(name, settings)
	if err != nil {
		showErrorCustom(dlg, chainTitle, chainCheckSaveError+err.Error())
	}
}

// onBlockUntunneledTrafficCBCheckedChanged has taken the name of the upstream
// handler, which used to rewrite AllowedIPs behind the user's back. The boxes
// are written when Save is clicked, so there is nothing to do here.
func (dlg *EditDialog) onBlockUntunneledTrafficCBCheckedChanged() {
}

// onBlockUntunneledTrafficStateChanged is what the editor calls when
// AllowedIPs change. The box no longer follows AllowedIPs.
func (dlg *EditDialog) onBlockUntunneledTrafficStateChanged(state int) {
}
