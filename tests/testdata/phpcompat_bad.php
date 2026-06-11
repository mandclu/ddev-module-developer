<?php
// Uses each(), which was removed in PHP 8.0.
// phpcompat (PHPCompatibility with PHP 8.2 target) must flag this.
$arr = [1, 2, 3];
each($arr);
