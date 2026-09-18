/* SPDX-License-Identifier: MIT
 *
 * AwgChain pack 55: the Settings tab, next to the log. It holds what belongs
 * to the whole program: raising a tunnel when Windows starts, and what
 * happens to the lock when the program is closed for good.
 */

package ui

import (
	"sort"
	"strings"

	"github.com/lxn/walk"

	"github.com/amnezia-vpn/amneziawg-windows-client/manager"
)

type SettingsPage struct {
	*walk.TabPage
	raiseCB     *walk.CheckBox
	tunnelCombo *walk.ComboBox
	quitCB      *walk.CheckBox
	names       []string
	loading     bool
}

func NewSettingsPage() (*SettingsPage, error) {
	var disposables walk.Disposables
	defer disposables.Treat()

	sp := new(SettingsPage)
	var err error
	if sp.TabPage, err = walk.NewTabPage(); err != nil {
		return nil, err
	}
	disposables.Add(sp)

	sp.SetTitle(chainSettingsTabTitle)

	layout := walk.NewVBoxLayout()
	layout.SetMargins(walk.Margins{18, 18, 18, 18})
	layout.SetSpacing(8)
	if err = sp.SetLayout(layout); err != nil {
		return nil, err
	}

	header, err := walk.NewTextLabel(sp)
	if err != nil {
		return nil, err
	}
	header.SetText(chainSettingsHeader)

	if sp.raiseCB, err = walk.NewCheckBox(sp); err != nil {
		return nil, err
	}
	sp.raiseCB.SetText(chainSettingsRaiseLabel)
	sp.raiseCB.SetToolTipText(chainSettingsRaiseHint)
	sp.raiseCB.CheckedChanged().Attach(sp.save)

	pick, err := walk.NewComposite(sp)
	if err != nil {
		return nil, err
	}
	pickLayout := walk.NewHBoxLayout()
	pickLayout.SetMargins(walk.Margins{0, 0, 0, 0})
	pickLayout.SetSpacing(6)
	if err = pick.SetLayout(pickLayout); err != nil {
		return nil, err
	}

	pickLabel, err := walk.NewTextLabel(pick)
	if err != nil {
		return nil, err
	}
	pickLabel.SetText(chainSettingsPickLabel)

	if sp.tunnelCombo, err = walk.NewComboBox(pick); err != nil {
		return nil, err
	}
	sp.tunnelCombo.CurrentIndexChanged().Attach(sp.save)

	if _, err = walk.NewHSpacer(pick); err != nil {
		return nil, err
	}

	if sp.quitCB, err = walk.NewCheckBox(sp); err != nil {
		return nil, err
	}
	sp.quitCB.SetText(chainSettingsQuitLabel)
	sp.quitCB.SetToolTipText(chainSettingsQuitHint)
	sp.quitCB.CheckedChanged().Attach(sp.save)

	if _, err = walk.NewVSpacer(sp); err != nil {
		return nil, err
	}

	sp.VisibleChanged().Attach(func() {
		if sp.Visible() {
			sp.reload()
		}
	})

	sp.reload()

	disposables.Spare()
	return sp, nil
}

// reload fills the page from the manager without writing anything back.
func (sp *SettingsPage) reload() {
	sp.loading = true
	defer func() { sp.loading = false }()

	global, err := manager.IPCClientChainGlobal()
	if err != nil {
		return
	}

	names := make([]string, 0, 4)
	tunnels, err := manager.IPCClientTunnels()
	if err == nil {
		for i := range tunnels {
			names = append(names, tunnels[i].Name)
		}
		sort.Slice(names, func(i, j int) bool {
			return strings.ToLower(names[i]) < strings.ToLower(names[j])
		})
	}
	sp.names = names

	if len(names) == 0 {
		sp.tunnelCombo.SetModel([]string{chainSettingsNoTunnels})
		sp.tunnelCombo.SetCurrentIndex(0)
		sp.tunnelCombo.SetEnabled(false)
	} else {
		sp.tunnelCombo.SetModel(names)
		sp.tunnelCombo.SetEnabled(true)
		index := 0
		for i := range names {
			if strings.EqualFold(names[i], global.RaiseTunnel) {
				index = i
				break
			}
		}
		sp.tunnelCombo.SetCurrentIndex(index)
	}

	sp.raiseCB.SetChecked(global.RaiseOnStart)
	sp.quitCB.SetChecked(global.LiftLockOnQuit)
}

// save writes the page back to the manager, unless the page is being filled.
func (sp *SettingsPage) save() {
	if sp.loading {
		return
	}

	global := manager.ChainGlobalSettings{
		RaiseOnStart:   sp.raiseCB.Checked(),
		LiftLockOnQuit: sp.quitCB.Checked(),
	}
	index := sp.tunnelCombo.CurrentIndex()
	if index >= 0 && index < len(sp.names) {
		global.RaiseTunnel = sp.names[index]
	}

	err := manager.IPCClientChainGlobalSave(global)
	if err != nil {
		showErrorCustom(nil, chainSettingsTabTitle, chainSettingsSaveError+err.Error())
	}
}
