/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2021 WireGuard LLC. All Rights Reserved.
 */

package conf

import (
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/amnezia-vpn/amneziawg-windows/v3/conf/dpapi"
)

const configFileSuffix = ".conf.dpapi"
const configFileUnencryptedSuffix = ".conf"

func ListConfigNames() ([]string, error) {
	configFileDir, err := tunnelConfigurationsDirectory()
	if err != nil {
		return nil, err
	}
	files, err := os.ReadDir(configFileDir)
	if err != nil {
		return nil, err
	}
	configs := make([]string, len(files))
	i := 0
	for _, file := range files {
		if plainName, ok := plainConfigName(configFileDir, file); ok {
			// AwgChain: a plain config with no encrypted counterpart is a real tunnel
			// too, so the interface must see it in the list.
			configs[i] = plainName
			i++
			continue
		}
		name := filepath.Base(file.Name())
		if len(name) <= len(configFileSuffix) || !strings.HasSuffix(name, configFileSuffix) {
			continue
		}
		if !file.Type().IsRegular() {
			continue
		}
		info, err := file.Info()
		if err != nil {
			continue
		}
		if info.Mode().Perm()&0444 == 0 {
			continue
		}
		name = strings.TrimSuffix(name, configFileSuffix)
		if !TunnelNameIsValid(name) {
			continue
		}
		configs[i] = name
		i++
	}
	return configs[:i], nil
}

func LoadFromName(name string) (*Config, error) {
	configFileDir, err := tunnelConfigurationsDirectory()
	if err != nil {
		return nil, err
	}
	if plain, ok := chainPlainPath(configFileDir, name); ok {
		// AwgChain: a chain hop is owned by the chain tooling and lives in plain
		// text. Prefer it over any stale encrypted copy left by an earlier sweep.
		return LoadFromPath(plain)
	}
	if _, err := os.Stat(filepath.Join(configFileDir, name+configFileSuffix)); err != nil {
		plainPath := filepath.Join(configFileDir, name+configFileUnencryptedSuffix)
		if _, err := os.Stat(plainPath); err == nil {
			return LoadFromPath(plainPath)
		}
	}
	return LoadFromPath(filepath.Join(configFileDir, name+configFileSuffix))
}

func LoadFromPath(path string) (*Config, error) {
	name, err := NameFromPath(path)
	if err != nil {
		return nil, err
	}
	bytes, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if strings.HasSuffix(path, configFileSuffix) {
		bytes, err = dpapi.Decrypt(bytes, name)
		if err != nil {
			return nil, err
		}
	}
	return FromWgQuickWithUnknownEncoding(string(bytes), name)
}

func PathIsEncrypted(path string) bool {
	return strings.HasSuffix(filepath.Base(path), configFileSuffix)
}

func NameFromPath(path string) (string, error) {
	name := filepath.Base(path)
	if !((len(name) > len(configFileSuffix) && strings.HasSuffix(name, configFileSuffix)) ||
		(len(name) > len(configFileUnencryptedSuffix) && strings.HasSuffix(name, configFileUnencryptedSuffix))) {
		return "", errors.New("Path must end in either " + configFileSuffix + " or " + configFileUnencryptedSuffix)
	}
	if strings.HasSuffix(path, configFileSuffix) {
		name = strings.TrimSuffix(name, configFileSuffix)
	} else {
		name = strings.TrimSuffix(name, configFileUnencryptedSuffix)
	}
	if !TunnelNameIsValid(name) {
		return "", errors.New("Tunnel name is not valid")
	}
	return name, nil
}

func (config *Config) Save(overwrite bool) error {
	if !TunnelNameIsValid(config.Name) {
		return errors.New("Tunnel name is not valid")
	}
	configFileDir, err := tunnelConfigurationsDirectory()
	if err != nil {
		return err
	}
	if config.Interface.PinEndpointVia != "" {
		// AwgChain: a chain hop stays in plain text, so that the interface, the
		// batch tooling, the watchdog and the tunnel services all read one file.
		plainName := filepath.Join(configFileDir, config.Name+configFileUnencryptedSuffix)
		return writeLockedDownFile(plainName, overwrite, []byte(config.ToWgQuick()))
	}
	filename := filepath.Join(configFileDir, config.Name+configFileSuffix)
	bytes := []byte(config.ToWgQuick())
	bytes, err = dpapi.Encrypt(bytes, config.Name)
	if err != nil {
		return err
	}
	return writeLockedDownFile(filename, overwrite, bytes)
}

func (config *Config) Path() (string, error) {
	if !TunnelNameIsValid(config.Name) {
		return "", errors.New("Tunnel name is not valid")
	}
	configFileDir, err := tunnelConfigurationsDirectory()
	if err != nil {
		return "", err
	}
	if plain, ok := chainPlainPath(configFileDir, config.Name); ok {
		// AwgChain: this is the path the tunnel service will be pointed at.
		return plain, nil
	}
	return filepath.Join(configFileDir, config.Name+configFileSuffix), nil
}

func DeleteName(name string) error {
	if !TunnelNameIsValid(name) {
		return errors.New("Tunnel name is not valid")
	}
	configFileDir, err := tunnelConfigurationsDirectory()
	if err != nil {
		return err
	}
	removedAny := false
	var lastErr error
	for _, suffix := range []string{configFileSuffix, configFileUnencryptedSuffix} {
		if rmErr := os.Remove(filepath.Join(configFileDir, name+suffix)); rmErr != nil {
			if !os.IsNotExist(rmErr) {
				lastErr = rmErr
			}
		} else {
			removedAny = true
		}
	}
	if lastErr != nil && !removedAny {
		return lastErr
	}
	return nil
}

func (config *Config) Delete() error {
	return DeleteName(config.Name)
}
