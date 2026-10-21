/* ==========================================================================
   mpv-redesigned - hero background
   --------------------------------------------------------------------------
   A slow drift of a few thousand points plus three translucent "glass" planes
   rendered with additive blending, sitting behind the hero copy.

   Design rules:
     * capped devicePixelRatio of 2, no antialias, additive blending only
     * requestAnimationFrame loop that stops when the tab is hidden
     * prefers-reduced-motion renders exactly one static frame
     * every geometry, material and the renderer itself are disposed on
       pagehide so nothing is left behind
   ========================================================================== */
(function (global) {
  'use strict';

  var reduceMotionQuery = global.matchMedia
    ? global.matchMedia('(prefers-reduced-motion: reduce)')
    : { matches: false, addEventListener: function () {} };

  function prefersReducedMotion() {
    return !!reduceMotionQuery.matches;
  }

  function makePoints(THREE, count, spread, size, color, opacity) {
    var positions = new Float32Array(count * 3);
    var speeds = new Float32Array(count);
    var i;

    for (i = 0; i < count; i += 1) {
      positions[i * 3] = (Math.random() - 0.5) * spread;
      positions[i * 3 + 1] = (Math.random() - 0.5) * spread * 0.62;
      positions[i * 3 + 2] = (Math.random() - 0.5) * spread * 0.5 - 1.5;
      speeds[i] = 0.012 + Math.random() * 0.05;
    }

    var geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    var material = new THREE.PointsMaterial({
      color: color,
      size: size,
      sizeAttenuation: true,
      transparent: true,
      opacity: opacity,
      depthWrite: false,
      blending: THREE.AdditiveBlending
    });

    var points = new THREE.Points(geometry, material);
    points.userData.speeds = speeds;
    points.userData.spread = spread * 0.62;
    points.userData.base = positions.slice(0);
    return points;
  }

  function makePlane(THREE, width, height, color, opacity, z) {
    var geometry = new THREE.PlaneGeometry(width, height);
    var material = new THREE.MeshBasicMaterial({
      color: color,
      transparent: true,
      opacity: opacity,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending
    });
    var plane = new THREE.Mesh(geometry, material);
    plane.position.z = z;
    return plane;
  }

  function mount(container, options) {
    var THREE = global.THREE;
    if (!THREE || !container) return null;

    var opts = options || {};
    var scene = new THREE.Scene();
    var camera = new THREE.PerspectiveCamera(58, 1, 0.1, 100);
    camera.position.set(0, 0, 6.4);

    var renderer;
    try {
      renderer = new THREE.WebGLRenderer({
        alpha: true,
        antialias: false,
        powerPreference: 'low-power'
      });
    } catch (err) {
      return null;
    }

    renderer.setClearColor(0x000000, 0);
    renderer.setPixelRatio(Math.min(global.devicePixelRatio || 1, 2));
    renderer.domElement.setAttribute('aria-hidden', 'true');
    renderer.domElement.style.width = '100%';
    renderer.domElement.style.height = '100%';
    container.appendChild(renderer.domElement);

    var pointCount = opts.points || 2400;
    var fieldA = makePoints(THREE, pointCount, 16, 0.045, 0x8ea2ff, 0.75);
    var fieldB = makePoints(THREE, Math.round(pointCount * 0.45), 13, 0.03, 0x67e8f9, 0.55);
    scene.add(fieldA);
    scene.add(fieldB);

    var planes = [
      makePlane(THREE, 7.5, 7.5, 0x4f46e5, 0.075, -2.4),
      makePlane(THREE, 6.2, 6.2, 0xa21caf, 0.06, -1.7),
      makePlane(THREE, 5.4, 5.4, 0x0891b2, 0.05, -0.9)
    ];
    planes[0].position.set(-1.6, 0.9, -2.4);
    planes[1].position.set(2.1, -0.7, -1.7);
    planes[2].position.set(0.4, 1.3, -0.9);
    for (var p = 0; p < planes.length; p += 1) scene.add(planes[p]);

    var clock = { last: 0 };
    var frame = null;
    var running = false;
    var disposed = false;

    function resize() {
      var rect = container.getBoundingClientRect();
      var width = Math.max(1, Math.round(rect.width || container.offsetWidth || 1));
      var height = Math.max(1, Math.round(rect.height || container.offsetHeight || 1));
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
    }

    function drift(group, elapsed, rate) {
      var positions = group.geometry.getAttribute('position');
      var speeds = group.userData.speeds;
      var span = group.userData.spread;
      var array = positions.array;
      var i;
      for (i = 0; i < speeds.length; i += 1) {
        var y = array[i * 3 + 1] + speeds[i] * elapsed * rate;
        if (y > span * 0.5) y -= span;
        array[i * 3 + 1] = y;
      }
      positions.needsUpdate = true;
    }

    function render(timestamp) {
      if (disposed) return;
      var elapsed = clock.last ? (timestamp - clock.last) / 1000 : 0;
      clock.last = timestamp;

      drift(fieldA, elapsed, 0.55);
      drift(fieldB, elapsed, -0.38);

      fieldA.rotation.y += elapsed * 0.014;
      fieldB.rotation.y -= elapsed * 0.021;

      planes[0].rotation.z += elapsed * 0.05;
      planes[0].rotation.x += elapsed * 0.021;
      planes[1].rotation.z -= elapsed * 0.037;
      planes[1].rotation.y += elapsed * 0.016;
      planes[2].rotation.z += elapsed * 0.028;
      planes[2].rotation.y -= elapsed * 0.012;

      renderer.render(scene, camera);
    }

    function loop(timestamp) {
      if (!running || disposed) return;
      render(timestamp);
      frame = global.requestAnimationFrame(loop);
    }

    function start() {
      if (running || disposed) return;
      if (prefersReducedMotion()) {
        render(0);
        return;
      }
      running = true;
      clock.last = 0;
      frame = global.requestAnimationFrame(loop);
    }

    function stop() {
      running = false;
      if (frame) {
        global.cancelAnimationFrame(frame);
        frame = null;
      }
    }

    function onVisibility() {
      if (document.hidden) {
        stop();
      } else {
        start();
      }
    }

    function dispose() {
      if (disposed) return;
      disposed = true;
      stop();
      document.removeEventListener('visibilitychange', onVisibility);
      global.removeEventListener('resize', resize);
      global.removeEventListener('pagehide', dispose);

      scene.traverse(function (object) {
        if (object.geometry && object.geometry.dispose) object.geometry.dispose();
        if (object.material && object.material.dispose) object.material.dispose();
      });
      scene.clear();
      if (renderer.domElement && renderer.domElement.parentNode) {
        renderer.domElement.parentNode.removeChild(renderer.domElement);
      }
      if (renderer.dispose) renderer.dispose();
      if (renderer.forceContextLoss) renderer.forceContextLoss();
    }

    resize();
    global.addEventListener('resize', resize);
    document.addEventListener('visibilitychange', onVisibility);
    global.addEventListener('pagehide', dispose);

    if (prefersReducedMotion()) {
      render(0);
    } else {
      start();
    }

    return {
      start: start,
      stop: stop,
      dispose: dispose,
      renderer: renderer
    };
  }

  global.MPVRThree = {
    mount: mount,
    prefersReducedMotion: prefersReducedMotion
  };
})(window);
