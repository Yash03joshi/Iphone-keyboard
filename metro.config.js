const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// The Swift iOS keyboard (built with xtool) has huge build folders; keep Metro out of it.
config.resolver.blockList = [].concat(config.resolver.blockList ?? [], [/\/ios-keyboard\/.*/]);

module.exports = config;
