package ui

import (
	"github.com/lxn/walk"
	"github.com/amnezia-vpn/amneziawg-windows/v3/conf"
)

// Patch 54: the dialog answers come from walk, not from raw numbers.

// Выбор ролей звеньев. Если оценка уверенная, спрашивать не нужно.
// Иначе показываем окно и спрашиваем, какой конфиг внешний (WARP).
func chainPickRoles(owner walk.Form, configs []*conf.Config) (*conf.Config, *conf.Config, bool) {
	if len(configs) < 2 {
		return nil, nil, false
	}
	a := configs[0]
	b := configs[1]

	outer, inner, sure := conf.ChainSortRolesScored(a, b)
	if sure {
		return outer, inner, true
	}

	text := "Не удаётся точно определить, какой конфиг внешний (WARP).\r\n\r\n" +
		"Да - внешним будет: " + a.Name + "\r\n" +
		"    " + conf.ChainRoleHint(a) + "\r\n\r\n" +
		"Нет - внешним будет: " + b.Name + "\r\n" +
		"    " + conf.ChainRoleHint(b) + "\r\n\r\n" +
		"Внешнее звено - то, что смотрит в интернет напрямую."

	res := walk.MsgBox(owner, "Какой конфиг внешний?", text, walk.MsgBoxYesNoCancel|walk.MsgBoxIconQuestion)
	switch res {
	case walk.DlgCmdYes:
		outer, inner = conf.ChainSortRolesForced(a, b, false)
		return outer, inner, true
	case walk.DlgCmdNo:
		outer, inner = conf.ChainSortRolesForced(a, b, true)
		return outer, inner, true
	}
	return nil, nil, false
}
