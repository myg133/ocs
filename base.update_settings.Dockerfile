FROM myg133/openvscode-server:base-latest

COPY ./base.settings.json /home/workspace/.openvscode-server/data/Machine/settings.json
