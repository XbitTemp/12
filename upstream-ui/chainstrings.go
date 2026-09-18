/* SPDX-License-Identifier: MIT
 *
 * AwgChain pack 55: every visible string of the new interface lives here.
 *
 * The patch scripts are pure ASCII by project rule, so they cannot carry
 * Russian text. This file is copied byte for byte instead.
 */

package ui

const (
	chainProtectLabel = "Защита от утечек:"
	chainProtectOn    = "включена"
	chainProtectOff   = "выключена"
	chainProtectOther = "включена для %s"
	chainProtectGuard = "включена (отдельной охраной)"
	chainProtectNoSvc = "неизвестна: служба не отвечает"

	chainCheckLockLabel = "Блокировать трафик мимо туннеля (kill switch)"
	chainCheckLockHint  = "Пока туннель поднят, наружу выпускаются только пакеты самой цепочки. Если снять галку, замок не ставится и при обрыве туннеля трафик пойдёт напрямую."
	chainCheckIPv6Label = "Блокировать IPv6"
	chainCheckIPv6Hint  = "IPv6 блокируется фильтром, пока туннель поднят. Адаптеры и настройки Windows не трогаются."
	chainCheckLANLabel  = "Разрешить локальную сеть"
	chainCheckLANHint   = "Принтеры, NAS, роутер и доступ к этой машине по локальной сети при закрытом замке."
	chainCheckSaveError = "Настройки туннеля не сохранены: "

	chainSettingsTabTitle   = "Настройки"
	chainSettingsHeader     = "Защита и автозапуск"
	chainSettingsRaiseLabel = "Поднимать туннель при старте Windows"
	chainSettingsRaiseHint  = "Служба поднимет выбранный туннель после загрузки, не дожидаясь входа в систему."
	chainSettingsPickLabel  = "Туннель:"
	chainSettingsQuitLabel  = "При выходе из программы опускать туннель и снимать замок"
	chainSettingsQuitHint   = "Выход через меню в трее. Закрытие окна крестиком ничего не меняет."
	chainSettingsNoTunnels  = "(туннелей нет)"
	chainSettingsSaveError  = "Настройки не сохранены: "
)
