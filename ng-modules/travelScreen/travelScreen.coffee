require('angular');

Tile = require('./Tile.coffee')
Sprite = require('./Sprite.coffee')

Randy = require('./ng-randy/ng-randy.coffee')

MIN_TRAVELS_PER_EVENT = 1000  # min amount of travel between events
EVENT_CONSISTENCY = 3  # affects variability in event timing. high values = more consistent timing. must be > 0
# units of EVENT_CONSISTENCY are fraction of MIN_TRAVELS_PER_EVENT, eg 3 means MIN_TRAV./3

# switching to javascript here...
`
var app = angular.module('travel-screen', [
    require('ng-hold'),
    require('game')
]);

app.directive("travelScreen", function() {
    return {
        restrict: 'E',
        templateUrl: "/ng-modules/travelScreen/travelScreen.html"
    };
});

app.controller("travelScreenController", ['$scope', 'data', '$interval', function($scope, data, $interval){
    var vm = this;
    vm.data = data;
    vm.randy = new Randy($scope);
    randyTime = 0;
    window.randy = vm.randy;  // for debug
    // TODO: do these need to be set after $(document).ready()?
    vm.canvasElement = document.getElementById("travelCanvas");
    vm.ctx = vm.canvasElement.getContext("2d");
    vm.shipImg = document.getElementById("player-ship");
    vm.shipW = 150;
    vm.shipH = 338;

    var timeoutId;

    vm.init = function(){
        vm.tiles = [new Tile(0, document.getElementById("bg-earth"))];
        vm.sprites = {}
        vm.shipY = 300;
        vm.shipX = 0;
        vm.travelling = false;
    }
    vm.init();
    $scope.$on('resetGame', vm.init);

    vm.startTravel = function(){
        vm.travelling = true;
        timeoutId = $interval(vm.go, TRAVEL_SPEED);
    }

    vm.go = function(){
        if (vm.travelling) vm.travel();
        else if (typeof timeoutId !== 'undefined') vm.stopTravel();
    }

    // PRIVATE FUNCTION
    var cancelInterval = function() {
        var result = $interval.cancel(timeoutId);
        if (result == true) timeoutId = undefined;
    }

    vm.stopTravel = function(){
        vm.travelling = false;
        cancelInterval();
    }
    $scope.$on('switchToModule', function(switchingTo){
        vm.stopTravel();
    });

    vm.toggleTravel = function(){
        if (vm.travelling){
            vm.stopTravel();
        } else {
            vm.startTravel();
        }
    };

    vm.getNextTile = function(xpos){
        // if distance travelled to destination big enough, append destination tile, else use filler
        return new Tile(xpos, document.getElementById("test-bg"));
    }

    vm.travel = function(){
        if (data.fuel >= data.fuelExpense) {
            data.travel();

            // move ship to optimal screen position
            if (vm.shipX < vm._getIdealShipPos()) {
                vm.shipX += 1;
                vm.data.distanceTraveled += 1
            } else {
                vm.shipX = vm._getIdealShipPos();
            }

            // move the tiles
            vm.tiles.forEach(function (tile) {
                tile.travel();
            });

            // remove old offscreen tiles
            while (vm.tiles[0].hasTravelledOffscreen()) {
                vm.tiles.splice(0, 1);  // remove leftmost tile
                console.log('tile removed');
            }

            // append new bg tiles if needed
            var overhang = vm.tiles[vm.tiles.length - 1].getOverhang();
            while (overhang < 100) {
                vm.tiles.push(vm.getNextTile(window.innerWidth + overhang));
                overhang = vm.tiles[vm.tiles.length - 1].getOverhang();
                console.log('tile added');
            }

            // handle arrival at stations/events
            var shipW = 150;
            for (var loc in data.locations) {
                var pos = data.locations[loc];
                if (pos < data.distanceTraveled && data.visited.indexOf(loc) < 0) {  // passing & not yet visited
                    data.visited.push(loc);
                    console.log('arrived at ', loc);
                    $scope.$emit('switchToModule', 'shop');
                }
            }

            // handle random events
            // TODO: if is a good time/place for an event
            if (randyTime > MIN_TRAVELS_PER_EVENT){
                if (randy.roll()){
                    randyTime = 0
                } else {
                    randyTime = MIN_TRAVELS_PER_EVENT/EVENT_CONSISTENCY
                }
            } else {
                randyTime += 1
            }
        }
        // TODO: else if within range of shop and have money, switch to shop screen module to buy fuel
        else { // end game
            vm.stopTravel();
            data.end();
        }
    }

    vm.drift = function(height){
        // returns slightly drifted modification on given height
        if (Math.random() < 0.01) {  // small chance of drift
            height += Math.round(Math.random() * 2 - 1);
            if (height > 400) {
                height = 399
            } else if (height < 200) {
                height = 201
            }
        }
        return height;
    }

    vm.drawSprite = function(location, Xposition){
        // draws location if in view at global Xposition
        var spriteW = 500;  // max sprite width (for checking when to draw)

        // if w/in reasonable draw distance
        if (data.distanceTraveled + window.innerWidth + spriteW > Xposition    // if close enough
            && data.distanceTraveled - spriteW < Xposition                  ) { // if we haven't passed it
            if (location in vm.sprites){  // if sprite already in current sprites
                var rel_x = Xposition-data.distanceTraveled;
                vm.sprites[location].x = rel_x
                // use existing y value (add small bit of drift)
                vm.sprites[location].y = vm.drift(vm.sprites[location].y);
                vm.sprites[location].draw(vm.ctx)
            } else {
                // get random y value and add to list of current sprites
                vm.sprites[location] = new Sprite(data.gameDir + '/assets/sprites/station_sheet.png',
                    -1000, Math.random()*200+200);
            }
            // TODO: remove sprites once we're done with them..
        }
    }

    vm.drawLocations = function(){
        for (var loc in data.locations){
            var pos = data.locations[loc] + vm.shipX + vm.shipW/2;
            vm.drawSprite(loc, pos);
        }
    }

    vm.drawBg = function(){
        vm.tiles.forEach(function(tile) {
            tile.draw(vm.ctx);
        });
    }

    vm.drawShip = function(){
        vm.shipY = vm.drift(vm.shipY);
        vm.ctx.drawImage(vm.shipImg, vm.shipX-vm.shipW/2, vm.shipY-vm.shipH/2);
    }

    vm.draw = function(){
        // resize element to window
        vm.ctx.canvas.width  = window.innerWidth;  //TODO: only do this when needed, not every draw
        vm.drawBg();
        vm.drawLocations();
        vm.drawShip();
    }
    $scope.$on('draw', vm.draw);

    vm._getIdealShipPos = function(){
        return window.innerWidth / 3
    }

    $scope.$on('encounter', function(args){
        // on random encounter
        console.log('adding encounter:', args);
        // TODO: place marker off screen & add to locations?
    });
}]);

module.exports = angular.module('travel-screen').name;
`