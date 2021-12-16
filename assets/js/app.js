// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import css from "../css/app.scss"

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured
// in "webpack.config.js".
//
// Import dependencies
//
import "bootstrap"
import "phoenix_html"

import "leaflet"
import "leaflet.markercluster"
import "leaflet.fullscreen"

import "leaflet/dist/leaflet.css"
import "leaflet.markercluster/dist/MarkerCluster.css"
import "leaflet.markercluster/dist/MarkerCluster.Default.css"
import "leaflet.fullscreen/Control.FullScreen.css"

// Import local files
//
// Local files can be imported directly using relative paths, for example:
// import socket from "./socket"

import "mdn-polyfills/CustomEvent"
import "mdn-polyfills/String.prototype.startsWith"
import "mdn-polyfills/Array.from"
import "mdn-polyfills/NodeList.prototype.forEach"
import "mdn-polyfills/Element.prototype.closest"
import "mdn-polyfills/Element.prototype.matches"
import "child-replace-with-polyfill"
import "url-search-params-polyfill"
import "formdata-polyfill"
import "classlist-polyfill"

import {
  Socket
} from "phoenix"
import {
  LiveSocket
} from "phoenix_live_view"

function car() {
  let group = document.createElementNS("http://www.w3.org/2000/svg", "g");

  let rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
  rect.setAttribute('stroke', 'black');
  rect.setAttribute('stroke-width', '0.5');
  rect.setAttribute('fill', "white");
  rect.setAttribute('x', 5);
  rect.setAttribute('y', 0);
  rect.setAttribute('height', 20);
  rect.setAttribute('width', 10);
  // group.appendChild(rect);

  let arrow_group = document.createElementNS("http://www.w3.org/2000/svg", "g");
  arrow_group.setAttribute('transform', `rotate(45,10,10)`);
  group.appendChild(arrow_group);

  let path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute('fill', "none");
  path.setAttribute('d', "M 0,0 L 5,0 M 0,0 L 0,5 M 0,0 L 20,20 M 15, 5 L 5, 15");
  path.setAttribute('stroke', 'red');
  path.setAttribute('stroke-width', '0.5');
  arrow_group.appendChild(path);

  return group;
}

function door(door_state, x, y, factor) {
  let group = document.createElementNS("http://www.w3.org/2000/svg", "g");
  group.setAttribute('transform', `translate(${x},${y})`);

  let rotate_group = document.createElementNS("http://www.w3.org/2000/svg", "g");
  rotate_group.setAttribute('transform', `rotate(${door_state*factor},0,0)`);
  group.appendChild(rotate_group);

  let line = document.createElementNS("http://www.w3.org/2000/svg", "line");
  line.setAttribute('fill', "none");
  line.setAttribute('x1', 0);
  line.setAttribute('y1', 0);
  line.setAttribute('x2', 0);
  line.setAttribute('y2', 10);
  rotate_group.appendChild(line);

  if (door_state > 0) {
    line.setAttribute('stroke', 'red');
    line.setAttribute('stroke-width', '1');
  } else {
    line.setAttribute('stroke', 'green');
    line.setAttribute('stroke-width', '0');
  }

  return group;
}


function trunk(door_state, x, y, factor) {
  let group = document.createElementNS("http://www.w3.org/2000/svg", "g");
  group.setAttribute('transform', `translate(${x},${y})`);

  let rotate_group = document.createElementNS("http://www.w3.org/2000/svg", "g");
  rotate_group.setAttribute('transform', `rotate(-90,0,0)`);
  group.appendChild(rotate_group);

  let line = document.createElementNS("http://www.w3.org/2000/svg", "line");
  line.setAttribute('fill', "none");
  line.setAttribute('x1', 0);
  line.setAttribute('y1', 0);
  line.setAttribute('x2', 0);
  line.setAttribute('y2', 10);
  rotate_group.appendChild(line);

  if (door_state > 0) {
    line.setAttribute('stroke', 'red');
    line.setAttribute('stroke-width', '1');
  } else {
    line.setAttribute('stroke', 'green');
    line.setAttribute('stroke-width', '0');
  }

  return group;
}

function pointer(tesla, el) {
  let bearing = tesla.heading;
  let door_df = tesla.doors_open;
  let door_dr = tesla.doors_open;
  let door_pf = tesla.doors_open;
  let door_pr = tesla.doors_open;
  let door_ft = tesla.frunk_open;
  let door_rt = tesla.trunk_open;

  let svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute('viewBox', '-5 -5 30 30');

  let group = document.createElementNS("http://www.w3.org/2000/svg", "g");
  group.setAttribute('transform', `rotate(${parseInt(bearing)},10,10)`);
  svg.appendChild(group);

  group.appendChild(car());
  group.appendChild(door(door_df, 15, 0, -10));
  group.appendChild(door(door_dr, 15, 10, -10));
  group.appendChild(door(door_pf, 5, 0, 10));
  group.appendChild(door(door_pr, 5, 10, 10));

  group.appendChild(trunk(door_ft, 5, 0, 1));
  group.appendChild(trunk(door_rt, 5, 20, 1));

  let s = new XMLSerializer();
  let str = s.serializeToString(svg);
  str = `data:image/svg+xml;utf8,${str}`;

  return L.icon({
    iconUrl: str,
    iconSize: [64, 64],
    iconAnchor: [32, 32],
  });
}

let Hooks = {};
let map = null;
let markers = null;
let tesla_marker = null;
let people = {};

Hooks.MapDetails = {
  updated() {
    if (tesla_marker != null) {
      tesla_marker.setPopupContent(this.el.firstElementChild.cloneNode(true));
    }
  }
}

Hooks.Map = {
  mounted() {
    map = L.map('mapid', {
      fullscreenControl: true,
    });

    // create the tile layer with correct attribution
    let osmUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
    let osmAttrib = 'Map data © <a href="https://openstreetmap.org">OpenStreetMap</a> contributors';
    let osm = new L.TileLayer(osmUrl, {
      minZoom: 8,
      maxZoom: 19,
      attribution: osmAttrib
    });
    map.addLayer(osm);

    // map.setView([latitude, longitude], 16);
    markers = L.markerClusterGroup().addTo(map);

    this.handleEvent("person", (person) => {
      let id = person.id;
      let latitude = person.location.latitude;
      let longitude = person.location.longitude;
      let icon = L.icon({
        iconUrl: person.avatar,
        iconSize: [67, 72],
        iconAnchor: [33, 36],
      })
      if (people[id]) {
        console.log("old person", id, person, people[id]);
        people[id].setLatLng([latitude, longitude]);
        people[id].setIcon(icon);
      } else {
        console.log("new person", id, person, people[id]);
        people[id] = L.marker([latitude, longitude], {
          icon: icon
        }).addTo(markers);
        people[id].bindPopup(`${person.firstName} ${person.lastName}`);
      }
    })

    this.handleEvent("tesla", (tesla) => {
      let latitude = tesla.latitude;
      let longitude = tesla.longitude;
      let the_pointer = pointer(tesla, this.el);
      if (tesla_marker) {
        console.log("old tesla", tesla, tesla_marker);
        tesla_marker.setLatLng([latitude, longitude]);
        tesla_marker.setIcon(the_pointer);
      } else {
        console.log("new tesla", tesla, tesla_marker);
        tesla_marker = L.marker([latitude, longitude], {
          icon: the_pointer,
        }).addTo(markers);
        tesla_marker.bindPopup(document.getElementById("details").cloneNode(true));
      }
      map.setView([latitude, longitude], 16);
    })
  },

  updated() {}
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  params: {
    _csrf_token: csrfToken
  },
  hooks: Hooks
});

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket