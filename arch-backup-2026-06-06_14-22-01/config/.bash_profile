#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

# React Native
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
