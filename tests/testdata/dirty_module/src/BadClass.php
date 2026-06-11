<?php

namespace Drupal\dirty_module;

/**
 * A class with intentional code quality issues for phpmd testing.
 */
class BadClass {

  /**
   * A method with an unused local variable (phpmd unusedcode violation).
   */
  public function badMethod() {
    $neverUsed = 'this variable is declared but never used';
    return TRUE;
  }

}
