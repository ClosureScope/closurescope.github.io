import { records } from './data';
import './style.css';
import './blog.css';

if (records.length) {
  void import('./main');
} else {
  document.querySelector('#empty-archive')?.removeAttribute('hidden');
}
